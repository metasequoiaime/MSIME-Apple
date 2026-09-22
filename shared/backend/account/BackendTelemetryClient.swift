import Foundation

/// Best-effort, privacy-preserving client telemetry. Events are queued on disk before the
/// network request so a transient offline period never loses a download or crash report.
public struct BackendTelemetryEvent: Codable, Equatable, Sendable {
  public let id: String
  public let kind: String
  public let platform: String
  public let version: String
  public let message: String?
  public let stack: String?

  public init(id: String = UUID().uuidString.lowercased(), kind: String, platform: String,
              version: String, message: String? = nil, stack: String? = nil) {
    self.id = id; self.kind = kind; self.platform = platform; self.version = version
    self.message = message; self.stack = stack
  }
}

public actor BackendTelemetryClient {
  public static let shared = BackendTelemetryClient()
  private let session: URLSession
  private let origin = URL(string: "https://api.msime.app")!
  private let queueURL: URL
  private let maxEvents = 64
  private let maxPayloadBytes = 64 * 1024

  public init(configuration: URLSessionConfiguration = .ephemeral, queueURL: URL? = nil) {
    let configuration = configuration.copy() as! URLSessionConfiguration
    configuration.httpCookieStorage = nil; configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    self.session = URLSession(configuration: configuration)
    self.queueURL = queueURL ?? Self.defaultQueueURL()
  }

  /// Record the first successful launch of this installation. The stable id makes this
  /// idempotent at the server and avoids counting every app launch as a download.
  public func recordFirstLaunch() {
    guard !UserDefaults.standard.bool(forKey: "msime.telemetry.firstLaunchRecorded") else {
      Task { await flush() }; return
    }
    UserDefaults.standard.set(true, forKey: "msime.telemetry.firstLaunchRecorded")
    enqueue(BackendTelemetryEvent(kind: "download", platform: Self.platform,
                                  version: Self.version))
    Task { await flush() }
  }

  public func recordCrash(message: String, stack: String? = nil) {
    let cleanMessage = String(message.prefix(2048))
    let cleanStack = stack.map { String($0.prefix(12_000)) }
    enqueue(BackendTelemetryEvent(kind: "crash", platform: Self.platform,
                                  version: Self.version, message: cleanMessage, stack: cleanStack))
    Task { await flush() }
  }

  /// Exception handlers run while the process is already unwinding; persist synchronously so the
  /// next launch can upload the report even if there is no time to schedule an async task.
  public nonisolated static func persistCrash(message: String, stack: String? = nil, queueURL: URL? = nil) {
    let event = BackendTelemetryEvent(kind: "crash", platform: platform, version: version,
                                      message: String(message.prefix(2048)),
                                      stack: stack.map { String($0.prefix(12_000)) })
    let url = queueURL ?? defaultQueueURL()
    var events = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([BackendTelemetryEvent].self, from: $0) } ?? []
    events.append(event); events = Array(events.suffix(64))
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
      try JSONEncoder().encode(events).write(to: url, options: [.atomic])
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    } catch { }
  }

  public func flush() async {
    var events = load()
    guard !events.isEmpty else { return }
    var pending: [BackendTelemetryEvent] = []
    for event in events {
      do {
        var request = URLRequest(url: origin.appendingPathComponent("v1/telemetry/events"))
        request.httpMethod = "POST"; request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MSIME/Telemetry", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONEncoder().encode(event)
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
          throw URLError(.badServerResponse)
        }
      } catch {
        pending.append(event)
      }
    }
    events = pending
    save(events)
  }

  private func enqueue(_ event: BackendTelemetryEvent) {
    var events = load()
    events.append(event)
    if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
    save(events)
  }

  private func load() -> [BackendTelemetryEvent] {
    guard let data = try? Data(contentsOf: queueURL), data.count <= maxPayloadBytes,
          let events = try? JSONDecoder().decode([BackendTelemetryEvent].self, from: data) else { return [] }
    return Array(events.suffix(maxEvents))
  }

  private func save(_ events: [BackendTelemetryEvent]) {
    guard let directory = queueURL.deletingLastPathComponent() as URL? else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
      let data = try JSONEncoder().encode(events)
      guard data.count <= maxPayloadBytes else { return }
      try data.write(to: queueURL, options: [.atomic])
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: queueURL.path)
    } catch { /* telemetry must never affect the host app */ }
  }

  private static var platform: String {
    #if os(iOS)
    return "ios"
    #elseif os(macOS)
    return "macos"
    #elseif os(Windows)
    return "windows"
    #elseif os(Android)
    return "android"
    #else
    return "unknown"
    #endif
  }

  private static var version: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
  }

  private static func defaultQueueURL() -> URL {
    #if os(iOS)
    if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.app.msime.ios") {
      return group.appendingPathComponent("telemetry-events.json")
    }
    #endif
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("MSIME/telemetry-events.json")
  }
}
