import AppKit
import SwiftUI

// One serial queue orders commits and user actions within this process; the shared
// store's file lock also covers a standalone settings process. No disk I/O on the IMK thread.
final class MacTypingStatistics: @unchecked Sendable {
  static let shared = MacTypingStatistics()
  private let queue = DispatchQueue(label: "app.msime.statistics", qos: .utility)
  private let configuredStore: TypingStatisticsStore?
  private lazy var store = configuredStore ?? TypingStatisticsStore()
  init(store: TypingStatisticsStore? = nil) { configuredStore = store }
  func record(_ text: String, source: TypingSource) {
    queue.async { try? self.store.record(text, source: source) }
  }
  func update(enabled: Bool? = nil, reset: Bool = false) async throws -> TypingStatistics {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          if let enabled { try self.store.setEnabled(enabled) }
          if reset { try self.store.reset() }
          continuation.resume(returning: try self.store.load())
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
}

@_cdecl("MSIMERecordTypingStatistics")
func recordTypingStatistics(_ text: UnsafePointer<CChar>?, _ source: UnsafePointer<CChar>?) {
  guard let text, let source else { return }
  MacTypingStatistics.shared.record(String(cString: text), source: TypingSource(rawValue: String(cString: source)) ?? .unknown)
}

@MainActor
final class MacStatisticsModel: ObservableObject {
  @Published var value = TypingStatistics()
  @Published var busy = false
  @Published var error: String?
  private let service: MacTypingStatistics
  init(service: MacTypingStatistics = .shared) { self.service = service }
  func refresh(enabled: Bool? = nil, reset: Bool = false) async {
    guard !busy else { return }
    busy = true
    defer { busy = false }
    do { value = try await service.update(enabled: enabled, reset: reset); error = nil }
    catch { self.error = "无法读取或保存本机统计，请检查磁盘空间和文件权限。" }
  }
}

private struct MacStatisticsView: View {
  @StateObject private var model = MacStatisticsModel()
  @State private var period = 7
  @State private var selectedDay: Date?
  @State private var confirmingReset = false
  private var dates: [Date] {
    (0..<(period == 0 ? 30 : period)).reversed().compactMap {
      Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: Date()))
    }
  }
  private var scope: [Date]? { selectedDay.map { [$0] } ?? (period == 0 ? nil : dates) }
  private var total: Int { scope?.reduce(0) { $0 + model.value.count(on: $1) } ?? model.value.total }
  private var breakdown: TypingBreakdown { model.value.breakdown(on: scope) }
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Picker("统计范围", selection: $period) {
          Text("近 7 天").tag(7); Text("近 30 天").tag(30); Text("累计").tag(0)
        }.pickerStyle(.segmented).onChange(of: period) { _ in selectedDay = nil }
        HStack {
          metric("今日输入", model.value.count(on: Date()))
          Spacer()
          metric(selectedDay.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "所选范围",
                 scope?.reduce(0) { $0 + model.value.count(on: $1) } ?? model.value.total)
        }
        GroupBox("每日趋势（点击查看当天）") {
          HStack(alignment: .bottom, spacing: 4) {
            ForEach(dates, id: \.self) { date in
              let count = model.value.count(on: date)
              let maximum = max(1, dates.map { model.value.count(on: $0) }.max() ?? 1)
              Button { selectedDay = date } label: {
                VStack {
                  Spacer(minLength: 0)
                  RoundedRectangle(cornerRadius: 3).fill(selectedDay == date ? Color.accentColor : Color.secondary.opacity(0.45))
                    .frame(height: max(3, 90 * CGFloat(count) / CGFloat(maximum)))
                  if period == 7 { Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2) }
                }.frame(maxWidth: .infinity).frame(height: 115)
              }.buttonStyle(.plain)
                .help("\(date.formatted(date: .abbreviated, time: .omitted))：\(count) 字符")
                .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted))，\(count) 字符")
            }
          }.padding(8)
        }
        if selectedDay != nil { Button("返回整个时间范围") { selectedDay = nil } }
        GroupBox("字符类型") {
          VStack {
            ForEach(TypingCharacterKind.allCases, id: \.rawValue) { kind in
              row(kind.title, count: breakdown.characters[kind.rawValue] ?? 0)
            }
          }.padding(8)
        }
        GroupBox("语言模式") {
          VStack {
            row("中文模式", count: ["quanpin", "shuangpin", "ziranma", "microsoft", "shoudao", "wubi"].reduce(0) { $0 + (breakdown.sources[$1] ?? 0) })
            row("英文模式", count: breakdown.sources["english"] ?? 0)
            row("本地输入", count: breakdown.sources["local"] ?? 0)
            row("语音输入", count: breakdown.sources["voice"] ?? 0)
            row("AI 润色与回复", count: (breakdown.sources["ai"] ?? 0) + (breakdown.sources["reply"] ?? 0))
            row("历史未分类", count: breakdown.sources["unknown"] ?? 0)
          }.padding(8)
        }
        Text("按提交时的输入模式分类，不推测文本语言；语音和 AI 单独按来源统计。")
          .font(.footnote).foregroundStyle(.secondary)
        GroupBox("输入来源") {
          VStack {
            ForEach([TypingSource.quanpin, .shuangpin, .ziranma, .microsoft, .shoudao, .wubi, .english, .local, .ai, .reply, .voice, .unknown], id: \.rawValue) { source in
              row(source == .quanpin ? "全拼" : source == .english ? "英文模式" : source.title,
                  count: breakdown.sources[source.rawValue] ?? 0)
            }
          }.padding(8)
        }
        Toggle("记录打字统计", isOn: Binding(get: { model.value.enabled }, set: { enabled in
          Task { await model.refresh(enabled: enabled) }
        })).disabled(model.busy)
        HStack {
          Button("刷新") { Task { await model.refresh() } }.keyboardShortcut("r", modifiers: .command)
          Button("清空统计…", role: .destructive) { confirmingReset = true }
          if model.busy { ProgressView().controlSize(.small) }
        }.disabled(model.busy)
        Text("仅记录水杉输入法上屏的字符分类和数量，不保存输入内容，不上传。空格、换行和未上屏拼音不计入，组合表情计一个字符。删除不扣减，其他应用自行处理的按键不计入。每日明细保留最近 366 个有记录的日期。")
          .font(.footnote).foregroundStyle(.secondary)
        if let error = model.error { Text(error).foregroundStyle(.secondary) }
      }.padding(24)
    }.frame(minWidth: 500, minHeight: 520)
      .task { await model.refresh() }
      .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
        Task { await model.refresh() }
      }
      .alert("清空本机打字统计？", isPresented: $confirmingReset) {
        Button("取消", role: .cancel) { }
        Button("清空统计", role: .destructive) { Task { await model.refresh(reset: true) } }
      } message: { Text("累计数量、每日趋势与分类记录将被清空，无法撤销。") }
  }
  private func metric(_ title: String, _ count: Int) -> some View {
    VStack(alignment: .leading) { Text(title).foregroundStyle(.secondary); Text(count.formatted()).font(.largeTitle).monospacedDigit() }
  }
  private func row(_ title: String, count: Int) -> some View {
    HStack {
      Text(title); Spacer(); Text(count.formatted()).monospacedDigit()
      Text((total == 0 ? 0 : Double(count) / Double(total)).formatted(.percent.precision(.fractionLength(1))))
        .monospacedDigit().foregroundStyle(.secondary).frame(width: 65, alignment: .trailing)
    }
  }
}

@MainActor
final class MacStatisticsWindow: NSWindowController {
  static let shared = MacStatisticsWindow()
  private init() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 720),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    super.init(window: window)
    window.title = "打字统计"; window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: MacStatisticsView()); window.center()
  }
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  func showStatistics() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}

@_cdecl("MSIMEShowTypingStatistics")
func showTypingStatistics() { Task { @MainActor in MacStatisticsWindow.shared.showStatistics() } }
