import Foundation
import Darwin

// A saved package is checked against the version opened by this editor.
@MainActor
struct SkinPackageRevision {
  let directory: URL
  let device: dev_t
  let inode: ino_t
  let manifest: Data
  var artworkURL: URL?
  var artwork: Data?
  static func capture(_ directory: URL) throws -> Self {
    var info = stat()
    guard lstat(directory.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR else {
      throw ServiceFailure(message: "原皮肤已移动或不再是普通文件夹，请重新打开。")
    }
    return Self(directory: directory, device: info.st_dev, inode: info.st_ino,
      manifest: try boundedData(directory.appendingPathComponent("skin.toml"), limit: 65_536))
  }
  private static func boundedData(_ url: URL, limit: Int) throws -> Data {
    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= limit else {
      throw ServiceFailure(message: "皮肤文件过大，无法更新。")
    }
    let data = try Data(contentsOf: url)
    guard data.count <= limit else { throw ServiceFailure(message: "皮肤文件过大，无法更新。") }
    return data
  }
  func verify() throws {
    let current = try Self.capture(directory)
    guard current.device == device, current.inode == inode, current.manifest == manifest else {
      throw ServiceFailure(message: "原皮肤已被修改，请重新打开后再更新。")
    }
    if let artworkURL, let artwork,
       try Self.boundedData(artworkURL, limit: MacSkinArtwork.maximumBytes) != artwork {
      throw ServiceFailure(message: "原皮肤插画已被修改，请重新打开后再更新。")
    }
  }
  func replace(using draft: MacGeneratedSkinDraft, validate: ((URL) throws -> Void)? = nil) throws -> Self {
    let contents = try draft.reviewedContents()
    guard let previewID = draft.directory?.lastPathComponent else { throw ServiceFailure(message: "请先更新预览。") }
    let id = directory.lastPathComponent
    var text = String(decoding: contents.manifest, as: UTF8.self)
    let sourceID = "\nid = \"\(previewID)\"\n"
    guard text.contains(sourceID) else { throw ServiceFailure(message: "皮肤预览标识无效。") }
    text = text.replacingOccurrences(of: sourceID, with: "\nid = \"\(id)\"\n")
    let imageName = "msime-artwork-" + UUID().uuidString.lowercased() + ".png"
    if contents.artwork != nil { text = text.replacingOccurrences(of: "preview = \"artwork.png\"", with: "preview = \"\(imageName)\"") }
    let data = Data(text.utf8)
    let stageRoot = FileManager.default.temporaryDirectory.appendingPathComponent("msime-update-" + UUID().uuidString)
    let stage = stageRoot.appendingPathComponent(id)
    defer { try? FileManager.default.removeItem(at: stageRoot) }
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
    try data.write(to: stage.appendingPathComponent("skin.toml"), options: .atomic)
    if let image = contents.artwork { try image.write(to: stage.appendingPathComponent(imageName), options: .atomic) }
    try (validate ?? MacGeneratedSkinDraft.validate)(stage)
    try verify()
    let imageURL = directory.appendingPathComponent(imageName)
    var wroteImage = false
    do {
      // Publish the new image first, then atomically switch the manifest reference.
      // Existing assets remain available to readers and are never overwritten.
      if let image = contents.artwork { try image.write(to: imageURL, options: .withoutOverwriting); wroteImage = true }
      try verify()
      try data.write(to: directory.appendingPathComponent("skin.toml"), options: .atomic)
    } catch {
      if wroteImage { try? FileManager.default.removeItem(at: imageURL) }
      throw error
    }
    return Self(directory: directory, device: device, inode: inode, manifest: data,
      artworkURL: contents.artwork == nil ? nil : imageURL, artwork: contents.artwork)
  }
}
