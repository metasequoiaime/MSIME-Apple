import Foundation
import Darwin

struct MacReplyTemplate: Codable, Equatable, Identifiable {
  let id: UUID
  let name: String
  let prompt: String
  let revision: Int
  var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 32 &&
    !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prompt.count <= 2000 && revision > 0 }
}

@MainActor
final class MacReplyTemplateStore {
  static let shared = MacReplyTemplateStore()
  private let file: URL
  init(file: URL? = nil) {
    self.file = file ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("MetasequoiaIME/ReplyTemplates.json")
  }
  private func locked<T>(_ action: () throws -> T) throws -> T {
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let descriptor = open(file.appendingPathExtension("lock").path, O_CREAT | O_RDWR, 0o600)
    guard descriptor >= 0 else { throw ServiceFailure(message: "无法打开本机回复模板。") }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw ServiceFailure(message: "回复模板正在更新，请稍后重试。") }
    defer { flock(descriptor, LOCK_UN) }
    return try action()
  }
  private func readUnlocked() throws -> [MacReplyTemplate] {
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
    guard size <= 800000 else { throw ServiceFailure(message: "本机回复模板文件过大。") }
    let values = try JSONDecoder().decode([MacReplyTemplate].self, from: Data(contentsOf: file))
    guard values.count <= 50, values.allSatisfy(\.valid), Set(values.map(\.id)).count == values.count else {
      throw ServiceFailure(message: "本机回复模板格式无效。")
    }
    return values
  }
  func read() throws -> [MacReplyTemplate] { try locked { try readUnlocked() } }
  func save(_ value: MacReplyTemplate) throws {
    guard value.valid else { throw ServiceFailure(message: "回复模板为空、过长或版本无效。") }
    try locked {
      var values = try readUnlocked()
      if let old = values.first(where: { $0.id == value.id }),
         old.revision > value.revision || (old.revision == value.revision && old != value) {
        throw ServiceFailure(message: "本机已有较新版本，请刷新社区页面。")
      }
      values.removeAll { $0.id == value.id }; values.append(value)
      guard values.count <= 50 else { throw ServiceFailure(message: "最多保存 50 个回复模板，请先移除不需要的模板。") }
      try write(values)
    }
  }
  func remove(_ id: UUID) throws { try locked { try write(readUnlocked().filter { $0.id != id }) } }
  private func write(_ values: [MacReplyTemplate]) throws {
    let data = try JSONEncoder().encode(values)
    guard data.count <= 800000 else { throw ServiceFailure(message: "回复模板总量过大。") }
    try data.write(to: file, options: .atomic)
  }
}
