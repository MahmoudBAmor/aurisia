import CryptoKit
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var modelPackChannel: FlutterMethodChannel?
  private let modelPackInstaller = BundledModelPackInstaller()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.aurisia/model_pack",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "materializeBundledPack" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self else {
        result(
          FlutterError(
            code: "MODEL_PACK_INSTALL_FAILED",
            message: "The model pack installer is unavailable.",
            details: nil
          )
        )
        return
      }
      self.modelPackInstaller.materialize(arguments: call.arguments, result: result)
    }
    modelPackChannel = channel
  }
}

private final class BundledModelPackInstaller {
  private let workQueue = DispatchQueue(label: "com.aurisia.model-pack-installer")
  private let safeName = try! NSRegularExpression(pattern: "^[A-Za-z0-9._-]+$")
  private let safeAssetRoot = try! NSRegularExpression(pattern: "^[A-Za-z0-9._/-]+$")
  private let sha256Pattern = try! NSRegularExpression(pattern: "^[a-fA-F0-9]{64}$")

  func materialize(arguments: Any?, result: @escaping FlutterResult) {
    workQueue.async {
      do {
        let paths = try self.materialize(arguments: arguments)
        DispatchQueue.main.async { result(paths) }
      } catch {
        DispatchQueue.main.async {
          result(
            FlutterError(
              code: "MODEL_PACK_INSTALL_FAILED",
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private func materialize(arguments: Any?) throws -> [String: String] {
    guard let arguments = arguments as? [String: Any] else {
      throw InstallerError.invalidArguments("Model pack arguments are missing.")
    }
    let packId = try requireSafeName(arguments["packId"] as? String, label: "packId")
    let version = try requireSafeName(arguments["version"] as? String, label: "version")
    let assetRoot = try requireAssetRoot(arguments["assetRoot"] as? String)
    guard let rawArtifacts = arguments["artifacts"] as? [[String: Any]], !rawArtifacts.isEmpty else {
      throw InstallerError.invalidArguments("The model pack has no artifacts.")
    }
    let artifacts = try rawArtifacts.map(parseArtifact)
    guard Set(artifacts.map(\.role)).count == artifacts.count else {
      throw InstallerError.invalidArguments("Model artifact roles must be unique.")
    }

    let fileManager = FileManager.default
    guard let applicationSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      throw InstallerError.fileSystem("Application Support is unavailable.")
    }
    var destination = applicationSupport
      .appendingPathComponent("model_packs", isDirectory: true)
      .appendingPathComponent(packId, isDirectory: true)
      .appendingPathComponent(version, isDirectory: true)
    try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    try destination.setResourceValues(resourceValues)

    var paths = [String: String]()
    for artifact in artifacts {
      paths[artifact.role] = try materializeArtifact(
        destination: destination,
        assetRoot: assetRoot,
        artifact: artifact
      ).path
    }
    return paths
  }

  private func materializeArtifact(
    destination: URL,
    assetRoot: String,
    artifact: Artifact
  ) throws -> URL {
    let fileManager = FileManager.default
    let target = destination.appendingPathComponent(artifact.path)
    let checksumMarker = destination.appendingPathComponent("\(artifact.path).sha256")
    if
      fileManager.fileExists(atPath: target.path),
      fileSize(target) == artifact.sizeBytes,
      (try? String(contentsOf: checksumMarker, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()) == artifact.sha256
    {
      return target
    }

    let flutterAsset = FlutterDartProject.lookupKey(
      forAsset: "\(assetRoot)/\(artifact.path)"
    )
    guard let sourcePath = Bundle.main.path(forResource: flutterAsset, ofType: nil) else {
      throw InstallerError.missingAsset(artifact.path)
    }
    let source = URL(fileURLWithPath: sourcePath)
    let partial = destination.appendingPathComponent("\(artifact.path).partial")
    if fileManager.fileExists(atPath: partial.path) {
      try fileManager.removeItem(at: partial)
    }

    let copied = try copyAndHash(source: source, destination: partial)
    guard copied.sizeBytes == artifact.sizeBytes, copied.sha256 == artifact.sha256 else {
      try? fileManager.removeItem(at: partial)
      throw InstallerError.verificationFailed(artifact.path)
    }

    if fileManager.fileExists(atPath: target.path) {
      try fileManager.removeItem(at: target)
    }
    try fileManager.moveItem(at: partial, to: target)
    try artifact.sha256.write(to: checksumMarker, atomically: true, encoding: .utf8)
    return target
  }

  private func copyAndHash(source: URL, destination: URL) throws -> CopyResult {
    guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
      throw InstallerError.fileSystem("Could not create a model file.")
    }
    let input = try FileHandle(forReadingFrom: source)
    let output = try FileHandle(forWritingTo: destination)
    defer {
      try? input.close()
      try? output.close()
    }

    var hasher = SHA256()
    var sizeBytes: Int64 = 0
    while true {
      let data = try input.read(upToCount: 1024 * 1024) ?? Data()
      if data.isEmpty {
        break
      }
      hasher.update(data: data)
      try output.write(contentsOf: data)
      sizeBytes += Int64(data.count)
    }
    try output.synchronize()
    let checksum = hasher.finalize().map { String(format: "%02x", $0) }.joined()
    return CopyResult(sizeBytes: sizeBytes, sha256: checksum)
  }

  private func fileSize(_ url: URL) -> Int64? {
    guard
      let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attributes[.size] as? NSNumber
    else {
      return nil
    }
    return size.int64Value
  }

  private func parseArtifact(_ value: [String: Any]) throws -> Artifact {
    let role = try requireSafeName(value["role"] as? String, label: "artifact role")
    let path = try requireSafeName(value["path"] as? String, label: "artifact path")
    guard
      let sha256 = value["sha256"] as? String,
      matches(sha256Pattern, value: sha256),
      let size = value["sizeBytes"] as? NSNumber,
      size.int64Value > 0
    else {
      throw InstallerError.invalidArguments("A model artifact is invalid.")
    }
    return Artifact(
      role: role,
      path: path,
      sha256: sha256.lowercased(),
      sizeBytes: size.int64Value
    )
  }

  private func requireSafeName(_ value: String?, label: String) throws -> String {
    guard let value, value != ".", value != "..", matches(safeName, value: value) else {
      throw InstallerError.invalidArguments("The \(label) is invalid.")
    }
    return value
  }

  private func requireAssetRoot(_ value: String?) throws -> String {
    guard
      let value,
      matches(safeAssetRoot, value: value),
      !value.contains("..")
    else {
      throw InstallerError.invalidArguments("The model asset root is invalid.")
    }
    return value
  }

  private func matches(_ pattern: NSRegularExpression, value: String) -> Bool {
    let range = NSRange(value.startIndex..<value.endIndex, in: value)
    return pattern.firstMatch(in: value, range: range) != nil
  }

  private struct Artifact {
    let role: String
    let path: String
    let sha256: String
    let sizeBytes: Int64
  }

  private struct CopyResult {
    let sizeBytes: Int64
    let sha256: String
  }

  private enum InstallerError: LocalizedError {
    case invalidArguments(String)
    case fileSystem(String)
    case missingAsset(String)
    case verificationFailed(String)

    var errorDescription: String? {
      switch self {
      case .invalidArguments(let message), .fileSystem(let message):
        return message
      case .missingAsset(let path):
        return "The bundled model asset \(path) was not found."
      case .verificationFailed(let path):
        return "Bundled model verification failed for \(path)."
      }
    }
  }
}
