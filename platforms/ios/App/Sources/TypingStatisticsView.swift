import SwiftUI

private typealias StatisticsSlice = StatisticsChart.Slice

/// 每一类配一个图标。名字是查出来的意思,不是装饰:九键是九宫格,双拼是两个键,五笔是笔画,手写是笔,语音是波形。
private enum StatisticsSymbol {
  static func source(_ source: TypingSource) -> String {
    switch source {
    case .quanpin: return "keyboard"
    case .nineKey: return "square.grid.3x3"
    case .shuangpin, .ziranma, .microsoft, .shoudao: return "square.on.square"
    case .wubi: return "scribble"
    case .japanese: return "character.bubble"
    case .handwriting: return "hand.draw"
    case .english: return "abc"
    case .local: return "clock.arrow.circlepath"
    case .ai: return "sparkles"
    case .reply: return "bubble.left.and.bubble.right"
    case .voice: return "waveform"
    case .unknown: return "questionmark.circle"
    }
  }
  static func kind(_ kind: TypingCharacterKind) -> String {
    switch kind {
    case .han: return "character.textbox"
    case .latin: return "textformat.abc"
    case .otherLetter: return "globe"
    case .number: return "number"
    case .punctuation: return "quote.opening"
    case .emoji: return "face.smiling"
    case .symbol: return "asterisk"
    case .unknown: return "questionmark.circle"
    }
  }
}

struct TypingStatisticsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var statistics = TypingStatistics()
  @State private var errorMessage = ""
  @State private var confirmsReset = false
  @State private var tab = Tab.trend
  @State private var selectedDay: Date?
  /// 占比条和图标的进场动画放过了没有。换标签时先归零再置起,这一块就重放一遍。
  @State private var revealed = false

  /// 三块内容轮流占这一屏,不再一路往下滚。
  private enum Tab: String, CaseIterable {
    case trend, kind, mode, scheme
    /// 标签只给两个字 —— 四格分段控件上放「语言模式」「输入方案」会挤成一行小字;全名在下面的分组标题里。
    var title: String {
      switch self {
      case .trend: return "趋势"
      case .kind: return "类型"
      case .mode: return "模式"
      case .scheme: return "方案"
      }
    }
  }

  /// 趋势画多少天。原来这里有个 7 / 30 / 累计 的切换,而分类那几块其实只想看累计 —— 一个开关同时管两件事,结果两件都得迁就它。
  private static let trendDays = 30
  private let store = TypingStatisticsStore()
  private let colors: [Color] = [.teal, .blue, .indigo, .orange, .pink, .purple, .brown, .gray]
  @State private var availability = TypingStatisticsStore.Availability.neverWritten
  // The old copy asked for Full Access unconditionally, so it said the same thing whether the
  // setting was the problem or not and carried no information. Each case here is a different
  // answer to "why is this empty", and a run that is working says nothing at all.
  private var storageAdvice: String? {
    switch availability {
    case .containerUnavailable:
      return "无法访问共享存储，键盘与本 app 之间没有可用的数据通道。重装水杉输入法可以重建它。"
    case .neverWritten:
      return "键盘从未写入过统计。请在系统设置 → 通用 → 键盘 → 键盘 → 水杉输入法中开启“允许完全访问”，"
        + "然后用水杉键盘输入几个字再回来刷新。未开启时仍可正常打字，只是不记录统计。"
    case .ready(let lastWritten):
      guard statistics.total == 0 else { return nil }
      guard let lastWritten else { return "统计文件存在但还没有计数，请用水杉键盘输入几个字再刷新。" }
      return "统计文件最后写入于 \(lastWritten.formatted(.dateTime.month().day().hour().minute()))，但计数为零。"
        + "若此前清空过统计，这是正常的；否则请附上这条信息反馈。"
    }
  }
  private var dates: [Date] {
    (0..<Self.trendDays).reversed().compactMap {
      Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: Date()))
    }
  }
  /// 点了某一天就只看那一天,否则看累计。
  private var scopeDates: [Date]? { selectedDay.map { [$0] } }
  private var breakdown: TypingBreakdown { statistics.breakdown(on: scopeDates) }
  private var scopeTotal: Int { scopeDates?.reduce(0) { $0 + statistics.count(on: $1) } ?? statistics.total }
  private var scopeTitle: String {
    if let selectedDay { return selectedDay.formatted(.dateTime.month().day()) }
    return "累计输入"
  }
  private var characterSlices: [StatisticsSlice] {
    TypingCharacterKind.allCases.enumerated().map { index, kind in
      StatisticsSlice(id: kind.rawValue, title: kind.title, count: breakdown.characters[kind.rawValue] ?? 0,
                      color: colors[index % colors.count], symbol: StatisticsSymbol.kind(kind))
    }
  }
  private var sourceSlices: [StatisticsSlice] {
    TypingSource.allCases.enumerated().map { index, source in
      StatisticsSlice(id: source.rawValue, title: source.title, count: breakdown.sources[source.rawValue] ?? 0,
                      color: colors[index % colors.count], symbol: StatisticsSymbol.source(source))
    }
  }
  private var languageSlices: [StatisticsSlice] {
    let sources = breakdown.sources
    return [
      StatisticsSlice(id: "chinese", title: "中文模式", count: ["quanpin", "nineKey", "shuangpin", "ziranma", "microsoft", "shoudao", "wubi"].reduce(0) { $0 + (sources[$1] ?? 0) }, color: .teal, symbol: "character.textbox"),
      StatisticsSlice(id: "japanese", title: "日语模式", count: sources["japanese"] ?? 0, color: .pink, symbol: "character.bubble"),
      StatisticsSlice(id: "english", title: "英文模式", count: sources["english"] ?? 0, color: .blue, symbol: "abc"),
      StatisticsSlice(id: "local", title: "本地输入", count: sources["local"] ?? 0, color: .purple, symbol: "clock.arrow.circlepath"),
      StatisticsSlice(id: "ai", title: "AI 润色", count: sources["ai"] ?? 0, color: .orange, symbol: "sparkles"),
      StatisticsSlice(id: "reply", title: "高情商回复", count: sources["reply"] ?? 0, color: .mint, symbol: "bubble.left.and.bubble.right"),
      StatisticsSlice(id: "voice", title: "语音输入", count: sources["voice"] ?? 0, color: .indigo, symbol: "waveform"),
      StatisticsSlice(id: "unknown", title: "历史未分类", count: sources["unknown"] ?? 0, color: .gray, symbol: "questionmark.circle"),
    ]
  }

  var body: some View {
    Form {
      Section {
        Picker("统计内容", selection: $tab) {
          ForEach(Tab.allCases, id: \.self) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented).accessibilityIdentifier("statisticsTab")
          .onChange(of: tab) { _ in replayReveal() }
        HStack {
          metric("今日输入", count: statistics.count(on: Date()), identifier: "typingToday")
          Spacer()
          metric(scopeTitle, count: scopeTotal, identifier: "typingTotal")
        }.padding(.vertical, 8)
      }
      switch tab {
      case .trend:
        Section {
          trendChart
          if selectedDay != nil {
            Button("返回累计") { selectedDay = nil }
          }
        } header: { Text("每日趋势 · 近 \(Self.trendDays) 天") }
          footer: { Text("折线是近 30 天的走势，方块是近 12 周每天的量；点一个方块只看那一天的分类与占比。") }
      case .kind:
        Section {
          distribution(characterSlices, chart: .pie)
        } header: { Text("字符类型") }
      case .mode:
        Section {
          distribution(languageSlices, chart: .donut)
        } header: { Text("语言模式") }
          footer: { Text("按提交时使用的键盘模式统计，不推测文本语言；中文模式下输入的数字仍计入中文模式。AI 润色和语音输入单独按来源统计。") }
      case .scheme:
        Section {
          distribution(sourceSlices, chart: .rank)
        } header: { Text("输入方案") }
          footer: { Text("拼音方案统计其上屏字符数，不计未上屏的拼音按键。旧版本总数保留为历史未分类，新输入开始记录细分。") }
      }
      // 开关、刷新和清空挪到了右上角的菜单:这一页是给人看数的,三个管理项挂在每一屏下面,每换一个标签都要再滚过它们一次。说明留在原处 —— 它解释的是屏幕上这些数字怎么来的。
      Section {
      } footer: {
        Text("仅统计水杉键盘提交的字符，含标点及表情，不含空格、换行和未上屏拼音。组合表情计为一个字符，删除文字不扣减。仅在本机保存分类计数，不保存输入内容。每日明细保留最近 366 个有记录的日期，累计分类持续保留。")
      }
      if let advice = storageAdvice {
        Section("统计没有数据") {
          Text(advice)
          Button("前往系统设置") {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
          }
        }
      }
      if !errorMessage.isEmpty { Section { Text(errorMessage).foregroundStyle(.secondary) } }
    }
    .navigationTitle("打字统计")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Menu {
          Button {
            update { try store.setEnabled(!statistics.enabled) }
          } label: {
            // 菜单里的开关用对勾表示开着 —— Toggle 放进 Menu 在 iOS 15 上画不出来。
            if statistics.enabled { Label("记录打字统计", systemImage: "checkmark") }
            else { Text("记录打字统计") }
          }
          .accessibilityIdentifier("typingStatisticsEnabled")
          Button("刷新统计") { reload() }
          Button("清空统计", role: .destructive) { confirmsReset = true }
            .accessibilityIdentifier("resetTypingStatistics")
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("统计选项")
        .accessibilityIdentifier("statisticsMenu")
      }
    }
    .onAppear { reload(); replayReveal() }
    .onChange(of: scenePhase) { if $0 == .active { reload() } }
    .alert("清空所有打字统计？", isPresented: $confirmsReset) {
      Button("取消", role: .cancel) {}
      Button("清空", role: .destructive) { update { try store.reset() }; selectedDay = nil }
    } message: { Text("累计字数、分类和每日记录将被删除，无法恢复。") }
  }

  /// 热力图看的是「哪些天在打字」,要看出习惯得比折线的窗口长 —— 三十天铺出来只有四五列,和折线说的是同一件事。
  private static let heatmapDays = 84
  private var heatmapDates: [Date] {
    (0..<Self.heatmapDays).reversed().compactMap {
      Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: Date()))
    }
  }

  private var trendChart: some View {
    let days = dates.map { StatisticsChart.Day(date: $0, count: statistics.count(on: $0)) }
    let heat = heatmapDates.map { StatisticsChart.Day(date: $0, count: statistics.count(on: $0)) }
    let maximum = days.map(\.count).max() ?? 0
    return VStack(alignment: .leading, spacing: 14) {
      Text("最高 \(maximum) 字符 / 天").font(.caption).foregroundStyle(.secondary)
      StatisticsTrendChart(days: days, selected: selectedDay,
                           accent: MetasequoiaTheme.forest, progress: revealed ? 1 : 0)
        .animation(.easeOut(duration: 0.7), value: revealed)
      // 折线看走势,热力图看「哪天在打字」—— 同一份数据的两个问题,一条线回答不了第二个。
      Text("近 \(Self.heatmapDays / 7) 周").font(.caption).foregroundStyle(.secondary)
      StatisticsHeatmap(days: heat, selected: selectedDay, accent: MetasequoiaTheme.forest) { date in
        selectedDay = selectedDay == date ? nil : date
      }
    }.padding(.vertical, 8).accessibilityElement(children: .contain).accessibilityIdentifier("statisticsTrend")
  }

  /// 一块分布 = 一张图 + 一份图例。图形按这一块回答的问题选,图例给准确数字。
  private func distribution(_ slices: [StatisticsSlice], chart: DistributionChart) -> some View {
    let total = slices.reduce(0) { $0 + $1.count }
    let visible = slices.filter { $0.count > 0 || $0.id != "unknown" }
    return VStack(spacing: 14) {
      switch chart {
      case .pie:
        StatisticsPieChart(slices: slices, progress: revealed ? 1 : 0)
      case .donut:
        StatisticsDonutChart(slices: slices, total: total, progress: revealed ? 1 : 0)
      case .rank:
        StatisticsRankChart(slices: slices, progress: revealed ? 1 : 0)
      }
      if total == 0, chart != .rank {
        Text("暂无输入记录").font(.subheadline).foregroundStyle(.secondary)
      }
      ForEach(Array(visible.enumerated()), id: \.element.id) { index, slice in
        HStack(spacing: 10) {
          Image(systemName: slice.symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(slice.color)
            .frame(width: 28, height: 28)
            .background(slice.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            .scaleEffect(revealed ? 1 : 0.6)
            .opacity(revealed ? 1 : 0)
            .animation(.spring(response: 0.42, dampingFraction: 0.72).delay(Double(index) * 0.03), value: revealed)
          Text(slice.title).font(.subheadline)
          Spacer()
          Text("\(slice.count)").monospacedDigit()
          Text(total == 0 ? "—" : "\(Double(slice.count) / Double(total) * 100, specifier: "%.1f")%")
            .font(.caption).foregroundStyle(.secondary).monospacedDigit().frame(width: 54, alignment: .trailing)
        }.accessibilityElement(children: .combine)
      }
    }.padding(.vertical, 8)
    .animation(.easeOut(duration: 0.6), value: revealed)
  }

  /// 这一块用哪种图。
  private enum DistributionChart { case pie, donut, rank }

  private func metric(_ title: String, count: Int, identifier: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.subheadline).foregroundStyle(.secondary)
      Text("\(count)").font(.system(size: 30, weight: .semibold, design: .rounded))
        .foregroundStyle(MetasequoiaTheme.forest).accessibilityIdentifier(identifier)
      Text("字符").font(.caption).foregroundStyle(.secondary)
    }
  }
  /// 动画从头放一遍。SwiftUI 只在值真的变了的时候动,所以要先落回起点。
  private func replayReveal() {
    revealed = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { revealed = true }
  }

  private func reload() { update {} }
  private func update(_ operation: () throws -> Void) {
    availability = store.availability()
    do {
      try operation()
      statistics = try store.load()
      errorMessage = ""
    } catch {
      // A locked device is one reason among several, and naming only that one sent a reader
      // looking in the wrong place. Carry what actually failed.
      errorMessage = "无法读取或保存统计：\(error.localizedDescription)"
    }
  }
}
