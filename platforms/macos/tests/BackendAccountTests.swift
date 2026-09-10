import AppKit
import Foundation
import Darwin

private final class MemoryCredentials: BackendSessionStorage, @unchecked Sendable {
  private let lock = NSLock()
  private var saved: BackendSavedSession?
  func load() throws -> BackendSavedSession? { lock.lock(); defer { lock.unlock() }; return saved }
  func save(_ value: BackendSavedSession) throws { lock.lock(); defer { lock.unlock() }; saved = value }
  func clear() throws { lock.lock(); defer { lock.unlock() }; saved = nil }
}
private final class AccountFixture: URLProtocol, @unchecked Sendable {
  static let generatedSkin = ##"{"name":"苔绿","light":{"surface":"#E8F0EB","border":"#D0DDD5","text":"#17251D","number":"#405048","selected":"#185C47","hover":"#D0DDD5","accent":"#185C47"},"dark":{"surface":"#17251D","border":"#405048","text":"#E8F0EB","number":"#D0DDD5","selected":"#185C47","hover":"#405048","accent":"#8ACCB0"}}"##
  static let fixtureLock = NSRecursiveLock()
  static var artworkJobs = 0
  static var artworkDeletes = 0
  static var artworkPNG = Data()
  static var artworkRunning = false
  private static var runningArtworkPolled = false
  static func hasPolledRunningArtwork() -> Bool {
    fixtureLock.lock(); defer { fixtureLock.unlock() }; return runningArtworkPolled
  }
  static var artworkPlans: String {
    let shapes = ["rounded", "capsule", "ticket"]
    let materials = ["flat", "raised", "glass"]
    let skins: [[String: Any]] = (0..<3).map { index in
      ["name":"方案\(index)", "description":"原创测试方案", "artworkPrompt":"森林插画场景\(index)",
       "background":"#FFFFFF", "keyBackground":"#FFFFFF", "keyForeground":"#000000", "accent":"#000000",
       "actionBackground":"#000000", "gradientHorizontal":false, "keyShape":shapes[index], "keyMaterial":materials[index],
       "cornerRadius":8, "borderWidth":0, "shadow":0.1, "pattern":0, "monospaced":false]
    }
    return String(data: try! JSONSerialization.data(withJSONObject: ["skins": skins]), encoding: .utf8)!
  }
  static let communitySkinID = UUID(uuidString: "a189598d-9b5b-4e3b-9f92-678028804bde")!
  static var communitySkinOwned = false
  static var communitySkinChanged = false
  static var communityDownloadChanged = false
  static var skinDownloads = 0
  static var publicationIDs: [String] = []
  static var publicationStatus = 200
  static var refreshes = 0
  static var expireCommunityOnce = false
  static var profileSyncSupported = false
  private static var preferenceRevision = 1
  private static var preferences: [String: Any] = ["platform.macos.candidate_font_size": 18, "platform.macos.candidate_learning": true, "platform.ios.nine_key": true]
  private static var clipboardEnabled = false
  private static var clipboardText: String?
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.fixtureLock.lock(); defer { Self.fixtureLock.unlock() }
    let body: String
    var status = 200
    var payload = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open(); defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 4096)
      while true { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; payload.append(contentsOf: buffer.prefix(count)) }
    }
    let values = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
    let itemID = String(repeating: "c", count: 64)
    func item(_ text: String) -> [String: String] { ["id": itemID, "text": text, "updated_at": "2026-09-08"] }
    func json(_ object: Any) -> String { String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)! }
    let skinPath = "/v1/community/skins/" + Self.communitySkinID.uuidString.lowercased()
    let design = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(CustomKeyboardSkin()))
    let communitySkin: [String: Any] = ["id": Self.communitySkinID.uuidString, "name": Self.communitySkinChanged ? "更新作品" : "庭院",
      "description":"测试配色", "author":"合成作者", "design":design, "downloads":Self.skinDownloads,
      "rating_count":0, "rating_average":0, "owned":Self.communitySkinOwned, "my_rating":0]
    switch (request.httpMethod!, request.url!.path) {
    case ("POST", "/v1/skins/jobs"):
      Self.artworkJobs += 1
      body = json(["id": String(format: "%048x", Self.artworkJobs), "state":"running"])
    case ("GET", let path) where path.hasPrefix("/v1/skins/jobs/"):
      if Self.artworkRunning { Self.runningArtworkPolled = true }
      body = json(["id":String(path.split(separator: "/").last!), "state":Self.artworkRunning ? "running" : "succeeded",
                   "artwork":["b64_json":Self.artworkPNG.base64EncodedString(), "mime_type":"image/png", "width":4, "height":4]])
    case ("DELETE", let path) where path.hasPrefix("/v1/skins/jobs/"):
      Self.artworkDeletes += 1; body = "{}"
    case ("GET", "/v1/community/skins"):
      if Self.expireCommunityOnce { Self.expireCommunityOnce = false; status = 401; body = "{}" }
      else { body = json(["skins":[communitySkin], "has_more":false]) }
    case ("POST", "/v1/community/skins"):
      Self.publicationIDs.append(values?["id"] as? String ?? "")
      status = Self.publicationStatus
      body = json(["id": values?["id"] as? String ?? ""])
      if status == 401 { Self.publicationStatus = 200 }
    case ("GET", skinPath): body = json(communitySkin)
    case ("POST", skinPath + "/download"):
      Self.skinDownloads += 1
      var downloaded = CustomKeyboardSkin()
      if Self.communityDownloadChanged { downloaded.background = 0 }
      body = json(["design":try! JSONSerialization.jsonObject(with: JSONEncoder().encode(downloaded))])
    case ("PUT", skinPath + "/rating"): body = "{\"stars\":5}"

    case ("GET", "/v1/models"):
      body = #"{"data":[{"id":"fixture-chat"}],"default_model":"fixture-chat"}"#
    case ("POST", "/v1/chat/completions"):
      let messages = values?["messages"] as? [[String: String]] ?? []
      let content = messages.first?["content"] == GeneratedCandidateSkin.instruction ? Self.generatedSkin : messages.first?["content"] == AISkinService.systemPrompt ? Self.artworkPlans : "回复：" + (messages.last?["content"] ?? "")
      body = json(["choices": [["message": ["role": "assistant", "content": content]]]])
    case ("GET", "/v1/users/me/preferences/schema"):
      var fields: [String: Any] = ["platform.macos.candidate_skin": ["type":"string", "maxLength":64], "platform.macos.candidate_font_size": ["type":"integer"], "platform.macos.candidate_learning": ["type":"boolean"], "platform.ios.nine_key": ["type":"boolean"]]
      if Self.profileSyncSupported { fields["input.shuangpin_schema"] = ["type":"string"] }
      body = json(["fields": fields, "maximum_bytes": 1048576, "update_mode": "replace", "revision_required": true])
    case ("GET", "/v1/users/me/preferences"):
      body = json(["revision":Self.preferenceRevision, "settings":Self.preferences])
    case ("PUT", "/v1/users/me/preferences"):
      if values?["revision"] as? Int == Self.preferenceRevision, let settings = values?["settings"] as? [String: Any] {
        Self.preferenceRevision += 1; Self.preferences = settings
        body = json(["revision":Self.preferenceRevision, "settings":Self.preferences])
      } else { body = "{}"; status = 409 }
    case ("PUT", "/v1/users/me/clipboard/settings"):
      Self.clipboardEnabled = values?["enabled"] as? Bool ?? false
      if !Self.clipboardEnabled { Self.clipboardText = nil }
      body = ""; status = 204
    case ("GET", "/v1/users/me/clipboard"):
      body = json(["enabled": Self.clipboardEnabled, "items": Self.clipboardText.map { [item($0)] } ?? []])
    case ("POST", "/v1/users/me/clipboard"):
      Self.clipboardText = values?["text"] as? String
      body = json(item(Self.clipboardText ?? ""))
    case ("DELETE", "/v1/users/me/clipboard"), ("DELETE", "/v1/users/me/clipboard/" + itemID):
      Self.clipboardText = nil; body = ""; status = 204
    case (_, "/v1/auth/providers"): body = #"{"providers":{"email":true,"phone":false,"apple":false}}"#
    case (_, "/v1/auth/challenges"): body = #"{"challenge_id":"synthetic","expires_in":300}"#
    case (_, "/v1/auth/login"), (_, "/v1/auth/refresh"):
      if request.url!.path.hasSuffix("/refresh") { Self.refreshes += 1 }
      let token = String(repeating: "a", count: 64), refresh = String(repeating: "b", count: 64)
      body = "{\"access_token\":\"\(token)\",\"refresh_token\":\"\(refresh)\",\"token_type\":\"Bearer\",\"expires_in\":900,\"user\":{\"id\":\"synthetic-user\",\"display_name\":\"测试\",\"created_at\":\"2026-09-08\"}}"
    case ("PATCH", "/v1/users/me"), (_, "/v1/auth/logout"): body = ""; status = 204
    case ("GET", "/v1/users/me"): body = #"{"user":{"id":"synthetic-user","display_name":"新昵称","created_at":"2026-09-08"},"identities":[]}"#
    case ("DELETE", "/v1/users/me"): body = #"{"error":{"code":"recent_login_required"}}"#; status = 403
    default: body = "{}"; status = 404
    }
    client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
@main struct AccountTests {
  struct Failure: Error {}
  @MainActor static func require(_ value: Bool) throws { if !value { throw Failure() } }
  @MainActor static func finished(_ model: MacAccountModel) async throws {
    let deadline = Date().addingTimeInterval(5)
    while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
    try require(!model.busy)
  }
  @MainActor static func finished(_ model: MacClipboardModel) async throws {
    let deadline = Date().addingTimeInterval(5)
    while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
    try require(!model.busy)
  }
  @MainActor static func finished(_ model: MacSettingsModel) async throws {
    let deadline = Date().addingTimeInterval(5)
    while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
    try require(!model.busy)
  }
  @MainActor static func finished(_ model: MacChatModel) async throws {
    let deadline = Date().addingTimeInterval(5)
    while model.busy && Date() < deadline { try await Task.sleep(nanoseconds: 5_000_000) }
    try require(!model.busy)
  }
  @MainActor static func chat(client: BackendAccountClient, session: BackendAccountSession) async throws {
    let chat = MacChatModel(accountID: "synthetic-user", client: client, account: session)
    chat.load(); try await finished(chat)
    try require(chat.selectedModel == "fixture-chat")
    chat.generateSkin(description: String(repeating: "字", count: 601))
    try require(chat.messages.isEmpty)
    chat.generateSkin(description: "苔绿庭院"); try await finished(chat)
    try require(chat.messages.count == 3 && chat.messages[0].text == GeneratedCandidateSkin.instruction)
    try require(GeneratedCandidateSkin.parse(chat.messages.last!.text).name == "苔绿")
    chat.clear()
    chat.draft = "  测试对话  "
    try require(chat.canSend)
    chat.send(); try await finished(chat)
    try require(chat.messages.count == 2 && chat.messages.last?.text == "回复：测试对话" && chat.draft.isEmpty)
    chat.draft = "第二轮"; chat.send(); try await finished(chat)
    try require(chat.messages.count == 4 && chat.messages.last?.text == "回复：第二轮")
    chat.draft = "停止后重试"; chat.send(); chat.stop()
    chat.retry(); try await finished(chat)
    try require(chat.messages.count == 6 && chat.messages.last?.text == "回复：停止后重试")
    chat.draft = String(repeating: "字", count: 6000)
    try require(!chat.canSend)
    chat.draft = "取消的消息"; chat.send(); chat.close()
    try await Task.sleep(nanoseconds: 50_000_000)
    try require(chat.messages.isEmpty && chat.models.isEmpty && !chat.busy)
    let writing = MacChatModel(accountID: "synthetic-user", client: client, account: session)
    writing.load(); try await finished(writing)
    writing.generateWriting(text: "  原始文字  ", task: .polish, style: "自然")
    try await finished(writing)
    try require(writing.messages.count == 3 && writing.messages[0].role == "system" &&
      writing.messages[0].text == WritingTask.polish.prompt(style: "自然") &&
      writing.messages[1].text == "原始文字" && writing.messages.last?.text == "回复：原始文字")
    writing.generateWriting(text: "对方的话", task: .reply, style: "委婉拒绝")
    try await finished(writing)
    try require(writing.messages.count == 3 && writing.messages[0].text == WritingTask.reply.prompt(style: "委婉拒绝") &&
      !writing.messages.contains(where: { $0.text == "原始文字" }))
    let previous = writing.messages.last?.id
    writing.generateWriting(text: String(repeating: "字", count: 6000), task: .reply, style: "自然")
    try require(!writing.busy && writing.error != nil && writing.messages.last?.id == previous)
    writing.generateWriting(text: "取消生成", task: .polish, style: "自然")
    writing.clear(); try await Task.sleep(nanoseconds: 50_000_000)
    try require(writing.messages.isEmpty && !writing.busy)
    writing.close()
    let wrongAccount = MacChatModel(accountID: "another-user", client: client, account: session)
    wrongAccount.load(); try await finished(wrongAccount)
    try require(wrongAccount.models.isEmpty)
  }
  @MainActor static func fileTransfer() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let source = directory.appendingPathComponent("backup.ndjson")
    let destination = directory.appendingPathComponent("saved.ndjson")
    let original = Data("existing backup".utf8), replacement = Data("new backup".utf8)
    try replacement.write(to: source); try original.write(to: destination)
    var authorizations = 0
    var rejected = false
    do {
      try await MacCloudFileTransfer.save(source, to: destination) {
        authorizations += 1
        if authorizations == 2 { throw CancellationError() }
      }
    } catch is CancellationError { rejected = true }
    try require(rejected && authorizations == 2)
    try require(try Data(contentsOf: destination) == original)
    try require(try Set(FileManager.default.contentsOfDirectory(atPath: directory.path)) == ["backup.ndjson", "saved.ndjson"])
    // A missing download must not destroy an existing user backup either.
    rejected = false
    do { try await MacCloudFileTransfer.save(directory.appendingPathComponent("missing"), to: destination) {} }
    catch { rejected = true }
    try require(rejected && (try Data(contentsOf: destination)) == original)
    try await MacCloudFileTransfer.save(source, to: destination) {}
    try require(try Data(contentsOf: destination) == replacement)
    try require(try Set(FileManager.default.contentsOfDirectory(atPath: directory.path)) == ["backup.ndjson", "saved.ndjson"])
  }
  @MainActor static func dictionaryMutationRetries() async throws {
    let busy = NSError(domain: "app.msime.snapshot", code: 423, userInfo: ["retryableDictionaryBusy": true])
    var attempts = 0
    let value: Int = try await MacDictionaryMutation.perform {
      attempts += 1
      if attempts == 1 { throw busy }
      return 7
    }
    try require(value == 7 && attempts == 2)
    attempts = 0
    do {
      let _: Int = try await MacDictionaryMutation.perform { attempts += 1; throw busy }
      throw Failure()
    } catch let error as NSError { try require(error.domain == busy.domain && attempts == 4) }
    attempts = 0
    do {
      let _: Int = try await MacDictionaryMutation.perform {
        attempts += 1; throw NSError(domain: "app.msime.snapshot", code: 423)
      }
      throw Failure()
    } catch { try require(attempts == 1) }
    let word = PersonalWord(key: "ni hao", value: "你好")
    var identifiers: [String] = []
    let model = MacPersonalDictionaryModel { selector, parameters in
      if selector == "page:" { return ["entries": [], "hasMore": false, "generation": "fixture"] }
      identifiers.append(parameters["identifier"] as! String)
      if identifiers.count == 1 { throw busy }
      return ["success": true]
    }
    model.load()
    try require(await model.save(previous: nil, replacement: word))
    try require(identifiers.count == 2 && identifiers[0] == identifiers[1])
    var called = 0
    let closing = MacPersonalDictionaryModel { selector, _ in
      if selector == "page:" { return ["entries": [], "hasMore": false, "generation": "fixture"] }
      called += 1; throw busy
    }
    closing.load()
    let save = Task { await closing.save(previous: nil, replacement: word) }
    try await Task.sleep(nanoseconds: 20_000_000)
    closing.cancelPendingWrites()
    try require(!(await save.value) && called == 1)
  }
  @MainActor static func personalDictionary() async throws {
    var identifiers: [String] = []
    var reject = true
    let word = PersonalWord(key: "ni hao", value: "你好")
    let model = MacPersonalDictionaryModel { selector, parameters in
      if selector == "page:" {
        return ["entries": [try MacPersonalDictionaryAccess.dictionary(word)], "hasMore": false, "generation": "fixture"]
      }
      try require(parameters["generation"] as? String == "fixture")
      identifiers.append(parameters["identifier"] as! String)
      if reject { throw Failure() }
      return ["success": true]
    }
    try require(!(await model.save(previous: nil, replacement: word)))
    model.load()
    try require(model.loaded && model.entries == [word])
    try require(!(await model.save(previous: nil, replacement: word)))
    reject = false
    try require(await model.save(previous: nil, replacement: word))
    try require(identifiers.count == 2 && identifiers[0] == identifiers[1])
    try require(await model.save(previous: word, replacement: nil))
    try require(identifiers.last != identifiers.first)
  }
  @MainActor static func statistics() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let service = MacTypingStatistics(store: TypingStatisticsStore(directory: directory))
    service.record("测试 A1 👨‍👩‍👧‍👦\n", source: .quanpin)
    var value = try await service.update()
    try require(value.total == 5 && value.detail.characters["han"] == 2 && value.detail.characters["emoji"] == 1)
    try require(value.detail.sources["quanpin"] == 5)
    let saved = try String(contentsOf: directory.appendingPathComponent("typing-statistics.json"), encoding: .utf8)
    try require(!saved.contains("测试") && !saved.contains("👨"))
    _ = try await service.update(enabled: false)
    service.record("关闭后不统计", source: .voice)
    value = try await service.update()
    try require(value.total == 5 && !value.enabled)
    value = try await service.update(reset: true)
    try require(value.total == 0 && value.days.isEmpty && value.detail.characters.isEmpty && !value.enabled)
    _ = try await service.update(enabled: true)
    service.record("语音", source: .voice)
    value = try await service.update()
    try require(value.total == 2 && value.detail.sources["voice"] == 2)
  }
  @MainActor static func replyTemplates(client: BackendAccountClient, session: BackendAccountSession) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = MacReplyTemplateStore(file: directory.appendingPathComponent("templates.json"))
    let template = MacReplyTemplate(id: UUID(), name: "温和拒绝", prompt: "用两句话礼貌拒绝，保留边界。", revision: 1)
    try store.save(template); try store.save(template)
    try require(try store.read() == [template])
    let model = MacChatModel(accountID: "synthetic-user", client: client, account: session, templates: store)
    model.load(); try await finished(model)
    model.generateWriting(text: "帮我做完这些吧", task: .reply, style: "自然", template: template)
    try await finished(model)
    try require(model.messages.count == 3 && model.messages[0].text == WritingTask.reply.prompt(style: "自然", templatePrompt: template.prompt))
    try await model.authorizeOutput()
    let update = MacReplyTemplate(id: template.id, name: template.name, prompt: "先致谢，再简洁拒绝。", revision: 2)
    try store.save(update)
    do { try await model.authorizeOutput(); throw NSError(domain: "stale-template-accepted", code: 1) }
    catch is ServiceFailure { }
    do { try store.save(template); throw NSError(domain: "template-downgrade-accepted", code: 1) }
    catch is ServiceFailure { }
    model.generateWriting(text: "原文", task: .polish, style: "自然", template: update)
    try await finished(model)
    try require(model.messages[0].text.contains("润色用户原文") && model.messages[0].text.contains(update.prompt))
    try store.remove(update.id)
    do { try await model.authorizeOutput(); throw NSError(domain: "removed-template-accepted", code: 1) }
    catch is ServiceFailure { }
    let invalid = MacReplyTemplate(id: UUID(), name: "", prompt: "", revision: 0)
    do { try store.save(invalid); throw NSError(domain: "invalid-template-accepted", code: 1) }
    catch is ServiceFailure { }
    try require(try store.read().isEmpty)
    for index in 0..<50 {
      try store.save(MacReplyTemplate(id: UUID(), name: "模板\(index)", prompt: "简洁回复", revision: 1))
    }
    do { try store.save(template); throw NSError(domain: "template-limit-ignored", code: 1) }
    catch is ServiceFailure { }
    try require(try store.read().count == 50)
    let descriptor = open(directory.appendingPathComponent("templates.json.lock").path, O_RDWR)
    try require(descriptor >= 0 && flock(descriptor, LOCK_EX | LOCK_NB) == 0)
    do { try store.remove(template.id); throw NSError(domain: "template-lock-bypassed", code: 1) }
    catch is ServiceFailure { }
    flock(descriptor, LOCK_UN); close(descriptor)
    model.close()
  }
  @MainActor static func customWriting(client: BackendAccountClient, session: BackendAccountSession) async throws {
    let defaults = UserDefaults.standard
    let previous = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
    defer { defaults.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
    var preferences: [String: Any] = ["service.ai.endpoint": "https://fixture.invalid/v1/chat/completions",
      "service.ai.model": "fixture-chat", "service.ai.prompt": "保留术语", MacWritingService.revisionKey: "one"]
    defaults.setVolatileDomain(preferences, forName: UserDefaults.argumentDomain)
    let configuration = MacWritingService.configuration
    let model = MacChatModel(accountID: "", client: client, account: session)
    model.generateCustomWriting(text: "原文", task: .polish, style: "自然", configuration: configuration) { config, text in
      try require(config.prompt.contains("保留术语") && config.prompt.contains("保持原意") && text == "原文")
      return "成稿"
    }
    try await finished(model)
    try require(model.messages.last?.text == "成稿" && model.error == nil)
    try await model.authorizeOutput()
    preferences[MacWritingService.revisionKey] = "two"
    defaults.setVolatileDomain(preferences, forName: UserDefaults.argumentDomain)
    do { try await model.authorizeOutput(); throw NSError(domain: "unexpected-authorization", code: 1) }
    catch is ServiceFailure { }
    model.generateCustomWriting(text: "回复原文", task: .reply, style: "委婉拒绝", configuration: configuration) { config, _ in
      try require(!config.prompt.contains("保留术语") && config.prompt.contains("代拟"))
      return "回复成稿"
    }
    try await finished(model)
    try require(model.messages.last?.text == "回复成稿")
    model.generateCustomWriting(text: "取消", task: .reply, style: "自然", configuration: configuration) { _, _ in
      try await Task.sleep(nanoseconds: 50_000_000); return "过期回复"
    }
    model.clear(); try await Task.sleep(nanoseconds: 70_000_000)
    try require(model.messages.isEmpty && !model.busy)
    let transport = URLSessionConfiguration.ephemeral
    transport.protocolClasses = [AccountFixture.self]
    let response = try await CustomServiceClient.request(kind: .ai, configuration: configuration,
      text: "网络原文", token: "synthetic-token", sessionConfiguration: transport)
    try require(response == "回复：网络原文")
    let body = try AppServicesBridge.polishBody("fixture-chat", prompt: "要求", text: "原文")
    let encoded = try JSONSerialization.jsonObject(with: body) as? [String: Any]
    try require(encoded?["model"] as? String == "fixture-chat")
    let parsed = try AppServicesBridge.parseResponse(Data(#"{"choices":[{"message":{"content":"成稿"}}]}"#.utf8), voice: false)
    try require(parsed == "成稿" && ServiceTokenStore.serviceIdentifier == "app.msime.macos.custom-services")
  }
  @MainActor static func writingContext() async throws {
    var valid = true, restored = false, writes = 0
    let check: @convention(block) () -> Bool = { valid }
    let restore: @convention(block) () -> Void = { restored = true }
    let cancel: @convention(block) () -> Void = { valid = false }
    let apply: @convention(block) (NSString, NSString) -> Bool = { text, source in
      guard valid, restored, text == "成稿", source == "polish" else { return false }
      writes += 1; valid = false; return true
    }
    let context = MacWritingContext(["text": "原文", "validate": check, "restore": restore,
      "cancel": cancel, "apply": apply] as NSDictionary)
    try require(context.text == "原文" && context.valid)
    let inserted = await context.apply("成稿", task: .polish)
    try require(inserted && restored && writes == 1)
    let repeated = await context.apply("成稿", task: .polish)
    try require(!repeated && writes == 1)
    valid = true; restored = false; context.cancel()
    let stale = await context.apply("成稿", task: .polish)
    try require(!stale && !restored && writes == 1)
    valid = true
    let pending = Task { await context.apply("成稿", task: .polish) }
    pending.cancel()
    let cancelled = await pending.value
    try require(!cancelled && writes == 1)
    valid = true; restored = false
    var authorizations = 0
    let rejected = await context.apply("成稿", task: .polish) {
      authorizations += 1
      // A previously authorized result becomes invalid while the host is activating.
      throw ServiceFailure(message: "账户已变化")
    }
    try require(!rejected && restored && authorizations == 1 && writes == 1)
    valid = true
    let invalidatedDuringAuthorization = await context.apply("成稿", task: .polish) {
      context.cancel()
    }
    try require(!invalidatedDuringAuthorization && writes == 1)
  }
  @MainActor static func communitySkins(client: BackendAccountClient, session: BackendAccountSession) async throws {
    func finish(_ model: MacCommunitySkinModel) async throws {
      for _ in 0..<200 where model.busy { try await Task.sleep(nanoseconds: 5_000_000) }
      try require(!model.busy)
    }
    let model = MacCommunitySkinModel(accountID: "synthetic-user", client: client, account: session)
    AccountFixture.expireCommunityOnce = true
    let refreshes = AccountFixture.refreshes
    model.load(); try await finish(model)
    try require(AccountFixture.refreshes == refreshes + 1)
    try require(model.items.count == 1 && !model.more)
    model.detail(AccountFixture.communitySkinID); try await finish(model)
    let reviewed = model.selected!
    let palette = try GeneratedCandidateSkin.community(name: reviewed.name, design: reviewed.design)
    try require(palette.light.surface == "#E8F0EB" && palette.dark.surface == palette.light.surface)
    var installed = 0
    model.download(reviewed: reviewed) { installed += 1 }; try await finish(model)
    try require(installed == 1 && AccountFixture.skinDownloads == 1)
    model.onlyMine = true
    try require(model.visibleItems.isEmpty && model.selected == nil)
    AccountFixture.communitySkinOwned = true
    model.load(); try await finish(model)
    try require(model.visibleItems.count == 1 && model.visibleItems[0].owned)
    AccountFixture.communitySkinOwned = false
    model.onlyMine = false
    model.load(); try await finish(model)
    try require(model.visibleItems.count == 1 && !model.visibleItems[0].owned)
    AccountFixture.communitySkinChanged = true
    model.download(reviewed: reviewed) { installed += 1 }; try await finish(model)
    try require(installed == 1 && AccountFixture.skinDownloads == 1 && model.message != nil)
    model.detail(reviewed.id); try await finish(model)
    try require(model.previewKey?.name == "更新作品")
    AccountFixture.communitySkinChanged = false
    AccountFixture.communityDownloadChanged = true
    model.download(reviewed: reviewed) { installed += 1 }; try await finish(model)
    try require(installed == 1 && AccountFixture.skinDownloads == 2)
    AccountFixture.communityDownloadChanged = false
    model.rate(reviewed, stars: 5); try await finish(model)
    try require(model.message == "评分已保存。")
    model.download(reviewed: reviewed) { installed += 1 }; model.close()
    try await Task.sleep(nanoseconds: 30_000_000)
    try require(installed == 1 && model.selected == nil && model.items.isEmpty)
    let wrong = MacCommunitySkinModel(accountID: "other-account", client: client, account: session)
    wrong.download(reviewed: reviewed) { installed += 1 }; try await finish(wrong)
    try require(installed == 1)
  }
  @MainActor static func skinPublication(client: BackendAccountClient, session: BackendAccountSession) async throws {
    func finish(_ model: MacSkinPublicationModel) async throws {
      for _ in 0..<200 where model.busy { try await Task.sleep(nanoseconds: 5_000_000) }
      try require(!model.busy)
    }
    let generated = try GeneratedCandidateSkin.parse(AccountFixture.generatedSkin)
    let design = try generated.communityDesign(dark: true)
    try require(design.background == 0x17251D && design.photo == nil)
    let source = SkinPublicationSource(name: generated.name, design: design)
    let model = MacSkinPublicationModel(accountID: "synthetic-user", source: source, client: client, account: session)
    model.name = ""; try require(!model.canPublish)
    model.name = source.name; model.description = String(repeating: "字", count: 281); try require(!model.canPublish)
    model.description = "测试发布"
    AccountFixture.publicationStatus = 503
    model.publish(); try await finish(model)
    try require(model.publishedID == nil && model.message != nil)
    let original = AccountFixture.publicationIDs.last!
    AccountFixture.publicationStatus = 200
    model.publish(); try await finish(model)
    try require(model.publishedID == UUID(uuidString: original) && AccountFixture.publicationIDs.last == original && !model.canPublish)
    let edited = MacSkinPublicationModel(accountID: "synthetic-user", source: source, client: client, account: session)
    AccountFixture.publicationStatus = 503
    edited.publish(); try await finish(edited)
    let before = AccountFixture.publicationIDs.last!
    edited.description = "修改后发布"
    AccountFixture.publicationStatus = 401
    let refreshes = AccountFixture.refreshes
    edited.publish(); try await finish(edited)
    try require(edited.publishedID != nil && edited.publishedID != UUID(uuidString: before) && AccountFixture.refreshes == refreshes + 1)
    try require(AccountFixture.publicationIDs.suffix(2).first == AccountFixture.publicationIDs.last)
    let count = AccountFixture.publicationIDs.count
    let wrong = MacSkinPublicationModel(accountID: "wrong-account", source: source, client: client, account: session)
    wrong.publish(); try await finish(wrong)
    try require(wrong.publishedID == nil && AccountFixture.publicationIDs.count == count)
    let cancelled = MacSkinPublicationModel(accountID: "synthetic-user", source: source, client: client, account: session)
    cancelled.publish(); cancelled.close()
    try await Task.sleep(nanoseconds: 30_000_000)
    try require(cancelled.publishedID == nil && !cancelled.busy)
  }
  @MainActor static func skinArtwork() throws {
    let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8,
      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    for x in 0..<4 { for y in 0..<4 { image.setColor(.systemGreen, atX: x, y: y) } }
    let png = image.representation(using: .png, properties: [:])!
    AccountFixture.artworkPNG = png
    let communityPhoto = try MacSkinArtwork.communityPhoto(png)
    try require(communityPhoto.count <= 512_000 && NSBitmapImageRep(data: communityPhoto)?.pixelsWide == 720)
    let normalized = try MacSkinArtwork.normalize(png)
    let decoded = NSBitmapImageRep(data: normalized)!
    try require(decoded.pixelsWide == 720 && decoded.pixelsHigh == 240)
    for invalid in [Data("not an image".utf8), Data(repeating: 0, count: MacSkinArtwork.maximumBytes + 1)] {
      do { _ = try MacSkinArtwork.normalize(invalid); throw Failure() }
      catch is Failure { throw Failure() } catch {}
    }
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var installed: String?
    let draft = MacGeneratedSkinDraft(validation: { _ in }, destination: { root }, select: { installed = $0 })
    try draft.prepare(AccountFixture.generatedSkin, artwork: png)
    let picture = draft.directory!.appendingPathComponent("artwork.png")
    let manifest = try String(contentsOf: draft.directory!.appendingPathComponent("skin.toml"), encoding: .utf8)
    try require(manifest.contains("preview = \"artwork.png\"") && manifest.contains("top_inset_dip = 80"))
    try Data("changed".utf8).write(to: picture)
    do { try draft.apply(); throw Failure() } catch is Failure { throw Failure() } catch {}
    try require(installed == nil)
    try draft.prepare(AccountFixture.generatedSkin, artwork: png)
    try draft.apply()
    let saved = root.appendingPathComponent(installed!).appendingPathComponent("artwork.png")
    try require(NSBitmapImageRep(data: Data(contentsOf: saved))?.pixelsWide == 720)
    draft.clear(); try require(FileManager.default.fileExists(atPath: saved.path))
    let editor = MacSkinEditorModel(draft: draft)
    try editor.load(JSONSerialization.jsonObject(with: Data(AccountFixture.generatedSkin.utf8)) as! [String: Any])
    editor.preview(); try require(editor.canApply)
    try editor.setArtwork(png); try require(!editor.canApply && editor.artwork != nil)
    editor.preview(); try require(editor.canApply)
    let publication = try editor.publication(dark: false)
    try require(publication.design.photo != nil && publication.design.photo!.count <= 512_000)
    try require(NSBitmapImageRep(data: publication.design.photo!)?.pixelsWide == 720)
    try editor.setArtwork(nil); try require(!editor.canApply && editor.artwork == nil)
    let palette = try JSONSerialization.jsonObject(with: Data(AccountFixture.generatedSkin.utf8)) as! [String: Any]
    try editor.loadPackage(root, read: { _ in ["palette":palette, "artwork":png] })
    try require(editor.hasReviewedDesign && editor.artwork != nil && editor.name == "苔绿")
    let retained = editor.artwork
    do {
      try editor.loadPackage(root, read: { _ in ["palette":palette, "artwork":Data("invalid".utf8)] })
      throw Failure()
    } catch is Failure { throw Failure() } catch {}
    try require(editor.hasReviewedDesign && editor.artwork == retained)
    try editor.loadPackage(root, read: { _ in ["palette":palette] })
    try require(editor.artwork == nil && editor.hasReviewedDesign)
    editor.close()
  }
  @MainActor static func savedSkinUpdate() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let id = UUID()
    let directory = root.appendingPathComponent(id.uuidString.lowercased())
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let skin = try GeneratedCandidateSkin.parse(AccountFixture.generatedSkin)
    let original = Data(skin.manifest(id: id, artwork: true).utf8)
    let manifestURL = directory.appendingPathComponent("skin.toml")
    let artworkURL = directory.appendingPathComponent("artwork.png")
    try original.write(to: manifestURL)
    let picture = try MacSkinArtwork.normalize(AccountFixture.artworkPNG)
    try picture.write(to: artworkURL)
    var revision = try SkinPackageRevision.capture(directory)
    revision.artworkURL = artworkURL; revision.artwork = picture
    let draft = MacGeneratedSkinDraft(validation: { _ in }, destination: { root }, select: { _ in })
    defer { draft.clear() }
    try draft.prepare(AccountFixture.generatedSkin.replacingOccurrences(of: "苔绿", with: "更新设计"), artwork: picture)
    do { _ = try revision.replace(using: draft, validate: { _ in throw Failure() }); throw Failure() }
    catch is Failure {}
    try require(Data(contentsOf: manifestURL) == original)
    try require(FileManager.default.contentsOfDirectory(atPath: directory.path).count == 2)
    let updated = try revision.replace(using: draft, validate: { stage in
      try require(stage.lastPathComponent == directory.lastPathComponent)
      try require(Data(contentsOf: manifestURL) == original)
    })
    let text = try String(contentsOf: manifestURL, encoding: .utf8)
    try require(text.contains("id = \"" + id.uuidString.lowercased() + "\"") && text.contains("更新设计"))
    try require(updated.artworkURL != artworkURL && updated.artworkURL != nil)
    try require(Data(contentsOf: updated.artworkURL!) == picture && Data(contentsOf: artworkURL) == picture)
    try updated.verify()
    do { _ = try revision.replace(using: draft, validate: { _ in }); throw Failure() }
    catch is Failure { throw Failure() } catch {}
    try require(String(contentsOf: manifestURL, encoding: .utf8) == text)
    try Data("changed picture".utf8).write(to: updated.artworkURL!)
    do { try updated.verify(); throw Failure() } catch is Failure { throw Failure() } catch {}
    try picture.write(to: updated.artworkURL!)
    try draft.prepare(AccountFixture.generatedSkin)
    let withoutPhoto = try updated.replace(using: draft, validate: { _ in })
    try require(withoutPhoto.artwork == nil && withoutPhoto.artworkURL == nil)
    try require(!String(contentsOf: manifestURL, encoding: .utf8).contains("preview ="))
    // An external rename between preview validation and publication must win.
    let external = Data("external change".utf8)
    do {
      _ = try withoutPhoto.replace(using: draft, validate: { _ in try external.write(to: manifestURL, options: .atomic) })
      throw Failure()
    } catch is Failure { throw Failure() } catch {}
    try require(Data(contentsOf: manifestURL) == external)
  }
  @MainActor static func skinEditor() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var selected: String?
    let draft = MacGeneratedSkinDraft(validation: { _ in }, destination: { root }, select: { selected = $0 })
    let editor = MacSkinEditorModel(draft: draft)
    try editor.load(JSONSerialization.jsonObject(with: Data(AccountFixture.generatedSkin.utf8)) as! [String: Any])
    try require(editor.light["surface"] == "#E8F0EB" && editor.dark["surface"] == "#17251D" && !editor.canApply)
    editor.preview()
    try require(editor.canApply && selected == nil)
    let sharedLight = try editor.publication(dark: false)
    let sharedDark = try editor.publication(dark: true)
    try require(sharedLight.design.background == 0xE8F0EB && sharedDark.design.background == 0x17251D)
    let oldPreview = draft.directory!
    editor.light["surface"] = "#ABCDEF"
    try require(!editor.canApply && editor.dark["surface"] == "#17251D")
    do { _ = try editor.publication(dark: false); throw Failure() } catch is Failure { throw Failure() } catch {}
    try require(sharedLight.design.background == 0xE8F0EB)
    editor.apply(); try require(selected == nil)
    editor.preview()
    try require(editor.canApply && !FileManager.default.fileExists(atPath: oldPreview.path))
    editor.apply()
    try require(selected != nil && !editor.canApply)
    try require(try editor.publication(dark: false).design.background == 0xABCDEF)
    let installed = root.appendingPathComponent(selected!).appendingPathComponent("skin.toml")
    try require(String(decoding: Data(contentsOf: installed), as: UTF8.self).contains("#ABCDEF"))
    editor.light["text"] = "invalid"
    editor.preview(); try require(editor.reviewed == nil && draft.directory == nil && editor.message != nil)
    editor.name = String(repeating: "字", count: 25)
    try require(editor.encoded == nil)
    editor.close()
    try require(FileManager.default.fileExists(atPath: installed.path))
  }
  @MainActor static func generatedSkinInstallation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var selected = "original"
    var validations = 0
    let draft = MacGeneratedSkinDraft(validation: { directory in
      try require(FileManager.default.fileExists(atPath: directory.appendingPathComponent("skin.toml").path))
      validations += 1
    }, destination: { root }, select: { selected = $0 })
    try draft.prepare(AccountFixture.generatedSkin)
    let preview = draft.directory!
    let expected = try Data(contentsOf: preview.appendingPathComponent("skin.toml"))
    try require(selected == "original" && validations == 1)
    try draft.apply()
    let installed = root.appendingPathComponent(selected)
    try require(draft.installed && validations == 2 && (try Data(contentsOf: installed.appendingPathComponent("skin.toml"))) == expected)
    draft.clear()
    try require(!FileManager.default.fileExists(atPath: preview.path) && FileManager.default.fileExists(atPath: installed.path))
    try draft.prepare(AccountFixture.generatedSkin)
    try Data("changed".utf8).write(to: draft.directory!.appendingPathComponent("skin.toml"))
    do { try draft.apply(); throw Failure() } catch is Failure { throw Failure() } catch {}
    try require(selected == installed.lastPathComponent)
    draft.clear()
    try draft.prepare(AccountFixture.generatedSkin)
    let collision = root.appendingPathComponent(draft.directory!.lastPathComponent)
    try FileManager.default.createDirectory(at: collision, withIntermediateDirectories: true)
    try Data("existing".utf8).write(to: collision.appendingPathComponent("skin.toml"))
    do { try draft.apply(); throw Failure() } catch is Failure { throw Failure() } catch {}
    try require((try Data(contentsOf: collision.appendingPathComponent("skin.toml"))) == Data("existing".utf8))
    draft.clear()
  }
  @MainActor static func clipboardHistory() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ClipboardHistoryStore(directory: directory)
    let model = MacClipboardHistoryModel(store: store)
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    board.setString("测试 COPY\n保留空格 ", forType: .string)
    model.refresh()
    try require(model.items.isEmpty) // Opening never captures.
    model.capture(from: board)
    let first = model.items[0]
    model.capture(from: board)
    try require(model.items.count == 1 && model.items[0].id == first.id)
    model.change(first.id, delete: false)
    for number in 0..<55 { try store.add("记录 \(number)") }
    model.refresh()
    try require(model.items.count == 50 && model.items.first?.id == first.id)
    model.search = "copy"
    try require(model.filtered.count == 1)
    for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"] {
      board.clearContents(); board.setString("秘密", forType: .string)
      board.setData(Data(), forType: NSPasteboard.PasteboardType(marker))
      model.capture(from: board)
      try require(model.message != nil && !(try store.load()).contains { $0.text == "秘密" })
    }
    model.copy(first.id, to: board)
    try require(board.string(forType: .string) == first.text)
    model.change(first.id, delete: true)
    board.clearContents(); board.setString("不替换", forType: .string)
    model.copy(first.id, to: board)
    try require(model.message != nil && board.string(forType: .string) == "不替换")
    try Data("invalid".utf8).write(to: store.file)
    model.capture(from: board)
    try require(model.message != nil && (try Data(contentsOf: store.file)) == Data("invalid".utf8))
    model.clear()
    try require(model.message == nil && model.items.isEmpty)
    try require(board.string(forType: .string) == "不替换")
    model.close()
    try require(model.search.isEmpty)
  }
  @MainActor static func main() async throws {
    try require(WritingTask.replyStyles.count == 9 && Set(WritingTask.replyStyles).count == 9)
    for style in WritingTask.replyStyles {
      try require(WritingTask.styles.contains(style) && WritingTask.reply.prompt(style: style).contains(style))
    }
    let skin = try GeneratedCandidateSkin.parse(AccountFixture.generatedSkin)
    let skinID = UUID(uuidString: "0F45DDBD-728B-4C55-9930-CB4B6CB0326D")!
    let manifest = skin.manifest(id: skinID)
    try require(manifest.contains("[candidate.light]") && manifest.contains("[candidate.dark]") && manifest.contains(skinID.uuidString.lowercased()))
    for invalid in [AccountFixture.generatedSkin.replacingOccurrences(of: "#E8F0EB", with: "url(file:///tmp/x)"),
                    AccountFixture.generatedSkin.replacingOccurrences(of: "苔绿", with: ""), "{}", String(repeating: "x", count: 16001)] {
      do { _ = try GeneratedCandidateSkin.parse(invalid); throw Failure() }
      catch is Failure { throw Failure() } catch {}
    }
    if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--export-generated-skin" {
      try Data(manifest.utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[2])); return
    }
    try skinArtwork()
    try savedSkinUpdate()
    try skinEditor()
    try generatedSkinInstallation()
    try clipboardHistory()
    try await writingContext()
    try await dictionaryMutationRetries()
    try await personalDictionary()
    try await statistics()
    try await fileTransfer()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [AccountFixture.self]
    let client = BackendAccountClient(configuration: configuration)
    let storage = MemoryCredentials()
    let session = BackendAccountSession(api: client, storage: storage)
    let model = MacAccountModel(client: client, account: session)
    model.load(); try await finished(model)
    try require(model.providers["email"] == true && model.user == nil)
    model.channel = "phone"; model.target = "+10000000000"
    model.requestCode(); try await finished(model)
    try require(model.challenge == nil && model.message != nil)
    model.channel = "email"; model.target = "synthetic@example.invalid"
    model.requestCode(); try await finished(model)
    try require(model.challenge != nil && model.resendAt > Date())
    model.code = "123456"; model.codeLogin(); try await finished(model)
    try require(model.user?.id == "synthetic-user" && model.code.isEmpty && model.target.isEmpty)
    let proposals = try await AISkinService.generate("原创森林", client: client, account: session, expectedUserID: "synthetic-user")
    try require(proposals.count == 3 && proposals.allSatisfy { $0.design.photo != nil })
    try require(AccountFixture.artworkJobs == 3 && AccountFixture.artworkDeletes == 3)
    do {
      _ = try await AISkinService.generate("测试", client: client, account: session, expectedUserID: "another-user")
      throw Failure()
    } catch { if error is Failure { throw error } }
    try require(AccountFixture.artworkJobs == 3)
    AccountFixture.artworkRunning = true
    let cancelled = Task { try await client.skinArtwork(prompt: "取消测试", account: session, userID: "synthetic-user") }
    for _ in 0..<100 {
      if AccountFixture.hasPolledRunningArtwork() { break }
      try await Task.sleep(nanoseconds: 10_000_000)
    }
    try require(AccountFixture.hasPolledRunningArtwork())
    cancelled.cancel()
    do { _ = try await cancelled.value; throw Failure() } catch is CancellationError {}
    try require(AccountFixture.artworkDeletes == 4)
    AccountFixture.artworkRunning = false
    try await chat(client: client, session: session)
    try await customWriting(client: client, session: session)
    try await replyTemplates(client: client, session: session)
    model.name = "新昵称"; model.rename(); try await finished(model)
    try require(model.user?.display_name == "新昵称" && storage.load()?.tokens.user.display_name == "新昵称")
    model.logout(delete: true); try await finished(model)
    try require(model.user != nil && model.message != nil && storage.load() != nil)
    try await communitySkins(client: client, session: session)
    try await skinPublication(client: client, session: session)
    var localSettings: MacSettingsAccess.Values = ["input.shuangpin_schema": .string("microsoft"), "platform.macos.candidate_skin": .string("wechat"), "platform.macos.candidate_font_size": .integer(16), "platform.macos.candidate_learning": .boolean(false)]
    let settings = MacSettingsModel(accountID: "synthetic-user", client: client, account: session, local: .init(snapshot: { localSettings }, validate: { values in
      guard values.count == 4 else { throw Failure() }
    }, apply: { localSettings = $0 }))
    settings.download(); try await finished(settings)
    try require(settings.preview?["platform.macos.candidate_font_size"] == .integer(18))
    try require(settings.preview?["platform.macos.candidate_skin"] == .string("wechat"))
    try require(settings.preview?["input.shuangpin_schema"] == .string("microsoft"))
    localSettings["platform.macos.candidate_font_size"] = .integer(20)
    settings.apply(); try await finished(settings)
    try require(settings.message != nil && localSettings["platform.macos.candidate_font_size"] == .integer(20))
    settings.download(); try await finished(settings)
    settings.apply(); try await finished(settings)
    try require(localSettings["platform.macos.candidate_font_size"] == .integer(18))
    settings.upload(); try await finished(settings)
    let credentials = try await session.credentials()
    let legacyPreferences = try await client.preferences(token: credentials.token)
    try require(legacyPreferences.settings["input.shuangpin_schema"] == nil)
    try require(settings.message?.contains("暂不支持双拼方案同步") == true)
    AccountFixture.profileSyncSupported = true
    settings.download(); try await finished(settings)
    settings.upload(); try await finished(settings)
    let savedPreferences = try await client.preferences(token: credentials.token)
    try require(savedPreferences.settings["platform.ios.nine_key"] == .boolean(true))
    try require(savedPreferences.settings["platform.macos.candidate_skin"] == .string("wechat"))
    try require(savedPreferences.settings["input.shuangpin_schema"] == .string("microsoft"))
    localSettings["input.shuangpin_schema"] = .string("xiaohe")
    settings.download(); try await finished(settings)
    try require(settings.preview?["input.shuangpin_schema"] == .string("microsoft"))
    settings.apply(); try await finished(settings)
    try require(localSettings["input.shuangpin_schema"] == .string("microsoft"))
    _ = try await client.putPreferences(savedPreferences, token: credentials.token)
    settings.upload(); try await finished(settings)
    try require(settings.message != nil)
    settings.close(); try require(settings.preview == nil && settings.cloud == nil)
    let clipboard = MacClipboardModel(accountID: "synthetic-user", client: client, account: session)
    clipboard.refresh(); try await finished(clipboard)
    try require(clipboard.loaded && !clipboard.enabled && clipboard.items.isEmpty)
    clipboard.setEnabled(true); try await finished(clipboard)
    clipboard.text = "合成剪贴板内容"; clipboard.upload(); try await finished(clipboard)
    try require(clipboard.items.first?.text == "合成剪贴板内容" && clipboard.text.isEmpty)
    clipboard.delete(id: clipboard.items.first!.id); try await finished(clipboard)
    try require(clipboard.items.isEmpty)
    clipboard.text = "合成清理内容"; clipboard.upload(); try await finished(clipboard)
    clipboard.setEnabled(false); try await finished(clipboard)
    try require(!clipboard.enabled && clipboard.items.isEmpty)
    let wrongAccount = MacClipboardModel(accountID: "previous-account", client: client, account: session)
    wrongAccount.refresh(); try await finished(wrongAccount)
    try require(!wrongAccount.loaded && wrongAccount.items.isEmpty)
    clipboard.text = "未上传的草稿"; clipboard.close()
    try require(clipboard.text.isEmpty && clipboard.items.isEmpty)
    model.logout(all: true); try await finished(model)
    try require(model.user == nil && storage.load() == nil)
    model.code = "123456"; model.target = "synthetic@example.invalid"; model.close()
    try require(model.code.isEmpty && model.target.isEmpty && model.challenge == nil)
    print("PASS: native chat model send, retry, cancellation and account binding; account model login, disabled provider, rename, failed deletion, logout and credential cleanup")
  }
}
