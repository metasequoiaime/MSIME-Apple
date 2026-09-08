import SwiftUI

struct CloudCandidatesView: View {
  let kind: BackendAccountClient.DictionaryKind
  let authorize: () async throws -> String
  @State private var text = ""
  @State private var scheme = "pinyin"
  @State private var profile = "xiaohe"
  @State private var jianpin = false
  @State private var mode = BackendAccountClient.RankingMode.pin
  @State private var step = 1
  @State private var trigger = 1
  @State private var forceTop = false
  @State private var position = 1
  @State private var page: BackendAccountClient.PersonalCandidates?
  @State private var query: BackendAccountClient.CandidateQuery?
  @State private var positions: [BackendAccountClient.FixedPosition] = []
  @State private var action: Action?
  @State private var busy = false
  @State private var message: String?
  @State private var pending: Task<Void, Never>?
  private let client = BackendAccountClient()
  private enum Action {
    case rank(BackendAccountClient.PersonalCandidate)
    case fix(BackendAccountClient.PersonalCandidate)
    case remove(BackendAccountClient.PersonalCandidate)
    case unfix(BackendAccountClient.FixedPosition)
    var title: String {
      switch self { case .rank: return "调整云端候选排序？"; case .fix: return "固定云端候选位置？"; case .remove: return "删除云端候选？"; case .unfix: return "取消固定位置？" }
    }
  }

  var body: some View {
    List {
      Section(kind.title) {
        TextField("输入编码", text: $text).backendCodeInput()
        if kind == .pinyin {
          Toggle("简拼候选", isOn: $jianpin)
          Picker("编码方案", selection: $scheme) { Text("全拼").tag("pinyin"); Text("双拼").tag("shuangpin") }
          if scheme == "shuangpin" {
            Picker("双拼方案", selection: $profile) {
              Text("小鹤").tag("xiaohe"); Text("自然码").tag("ziranma")
              Text("微软").tag("microsoft"); Text("Shoudao").tag("shoudao")
            }
          }
        }
        Button("查询云端候选") {
          run { try await load(.init(text: text, kind: jianpin && kind == .pinyin ? "jianpin" : kind.rawValue, scheme: scheme, profile: profile, limit: 100)) }
        }.disabled(text.isEmpty)
        Text("仅在点击查询时发送这里输入的编码。排序和固定位置由服务器输入引擎计算，修改保存到当前账号；本机键盘尚需完整同步才能采用云端状态。")
          .font(.footnote).foregroundStyle(.secondary)
      }
      if kind != .quick {
        Section("调频方式") {
          Picker("方式", selection: $mode) { ForEach(BackendAccountClient.RankingMode.allCases) { Text($0.title).tag($0) } }
          Stepper("线性步长：\(step)", value: $step, in: 1...100).disabled(mode != .linear)
          Stepper("触发次数：\(trigger)", value: $trigger, in: 1...10)
          Toggle("本次强制置顶", isOn: $forceTop)
          Stepper("固定到第 \(position) 位", value: $position, in: 1...5)
        }
      }
      if let page {
        Section("当前查询候选 · 版本 \(page.revision)") {
          if page.candidates.isEmpty { Text("没有匹配的候选。").foregroundStyle(.secondary) }
          ForEach(Array(page.candidates.enumerated()), id: \.element.id) { index, candidate in
            VStack(alignment: .leading, spacing: 6) {
              Text("\(index + 1). \(candidate.word)")
              Text("\(candidate.code) · 权重 \(candidate.weight)").font(.caption).foregroundStyle(.secondary)
              if kind != .quick {
                HStack {
                  Button("调频") { action = .rank(candidate) }
                  Button("固定") { action = .fix(candidate) }
                  Button("删除", role: .destructive) { action = .remove(candidate) }
                    .disabled(kind != .english && candidate.word.unicodeScalars.count <= 1)
                }.buttonStyle(.borderless)
              }
            }
          }
        }
        if !positions.isEmpty {
          Section("此查询的固定位置") {
            ForEach(positions) { item in
              HStack {
                Text("第 \(item.position) 位 · \(item.word)")
                Spacer()
                Button("取消固定") { action = .unfix(item) }.buttonStyle(.borderless)
              }
            }
          }
        }
      }
      if busy { ProgressView("正在处理…") }
      if let message { Text(message).foregroundStyle(.secondary) }
    }
    .navigationTitle("云端候选排序")
    .disabled(busy)
    .onDisappear { pending?.cancel(); page = nil; positions = [] }
    .alert(action?.title ?? "确认操作", isPresented: Binding(get: { action != nil }, set: { if !$0 { action = nil } })) {
      Button("取消", role: .cancel) { action = nil }
      Button("确认") {
        guard let selected = action, let page, let query else { return }
        run { try await apply(selected, page: page, query: query) }
        action = nil
      }
    } message: { Text("修改当前查询的云端状态；固定位置会替换该位置原有的词条。若其他设备已更新，需重新查询再确认。") }
  }
  @MainActor private func load(_ query: BackendAccountClient.CandidateQuery) async throws {
    let token = try await authorize()
    let result = try await client.personalCandidates(query, token: token)
    let fixed: [BackendAccountClient.FixedPosition]
    if query.kind != "quick" && !result.context.isEmpty { fixed = try await client.fixedPositions(context: result.context, token: token).positions }
    else { fixed = [] }
    _ = try await authorize()
    try Task.checkCancellation()
    self.query = query; page = result; positions = fixed
  }
  @MainActor private func apply(_ action: Action, page: BackendAccountClient.PersonalCandidates, query: BackendAccountClient.CandidateQuery) async throws {
    let token = try await authorize()
    var status = "云端状态已更新，本机设置保持原样。"
    switch action {
    case .rank(let candidate):
      let result = try await client.rankCandidate(candidate, query: query, revision: page.revision, mode: mode, step: step, trigger: trigger, forceTop: forceTop, token: token)
      status = result.changed ? "云端排序已更新。" : "已记录本次选择，本次未调整排序；累计 \(result.selection.count) 次。"
    case .fix(let candidate):
      _ = try await client.setFixedPosition(context: page.context, code: candidate.mutationCode, word: candidate.word, position: position, revision: page.revision, token: token)
    case .unfix(let item):
      _ = try await client.setFixedPosition(context: item.context, code: item.code, word: item.word, position: nil, revision: page.revision, token: token)
    case .remove(let candidate):
      _ = try await client.removeCandidate(candidate, query: query, revision: page.revision, token: token)
    }
    try await load(query)
    message = status
  }
  @MainActor private func run(_ work: @escaping @MainActor () async throws -> Void) {
    guard !busy else { return }
    busy = true; message = nil
    pending = Task {
      defer { busy = false }
      do { try await work() }
      catch is CancellationError { page = nil; positions = []; query = nil }
      catch { message = error.localizedDescription }
    }
  }
}
