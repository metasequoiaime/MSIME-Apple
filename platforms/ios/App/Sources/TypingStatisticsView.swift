import SwiftUI

private struct StatisticsSlice: Identifiable {
  let id: String
  let title: String
  let count: Int
  let color: Color
}

struct TypingStatisticsView: View {
  @Environment(\.scenePhase) private var scenePhase
  @State private var statistics = TypingStatistics()
  @State private var errorMessage = ""
  @State private var confirmsReset = false
  @State private var period = 7
  @State private var selectedDay: Date?
  private let store = TypingStatisticsStore()
  private let colors: [Color] = [.teal, .blue, .indigo, .orange, .pink, .purple, .brown, .gray]
  private var dates: [Date] {
    (0..<(period == 0 ? 30 : period)).reversed().compactMap {
      Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: Date()))
    }
  }
  private var scopeDates: [Date]? { selectedDay.map { [$0] } ?? (period == 0 ? nil : dates) }
  private var breakdown: TypingBreakdown { statistics.breakdown(on: scopeDates) }
  private var scopeTotal: Int { scopeDates?.reduce(0) { $0 + statistics.count(on: $1) } ?? statistics.total }
  private var scopeTitle: String {
    if let selectedDay { return selectedDay.formatted(.dateTime.month().day()) }
    return period == 0 ? "累计输入" : "近 \(period) 天输入"
  }
  private var characterSlices: [StatisticsSlice] {
    TypingCharacterKind.allCases.enumerated().map { index, kind in
      StatisticsSlice(id: kind.rawValue, title: kind.title, count: breakdown.characters[kind.rawValue] ?? 0, color: colors[index % colors.count])
    }
  }
  private var sourceSlices: [StatisticsSlice] {
    TypingSource.allCases.enumerated().map { index, source in
      StatisticsSlice(id: source.rawValue, title: source.title, count: breakdown.sources[source.rawValue] ?? 0, color: colors[index % colors.count])
    }
  }
  private var languageSlices: [StatisticsSlice] {
    let sources = breakdown.sources
    return [
      StatisticsSlice(id: "chinese", title: "中文模式", count: ["quanpin", "nineKey", "shuangpin", "ziranma", "microsoft", "shoudao", "wubi"].reduce(0) { $0 + (sources[$1] ?? 0) }, color: .teal),
      StatisticsSlice(id: "japanese", title: "日语模式", count: sources["japanese"] ?? 0, color: .pink),
      StatisticsSlice(id: "english", title: "英文模式", count: sources["english"] ?? 0, color: .blue),
      StatisticsSlice(id: "local", title: "本地输入", count: sources["local"] ?? 0, color: .purple),
      StatisticsSlice(id: "ai", title: "AI 润色", count: sources["ai"] ?? 0, color: .orange),
      StatisticsSlice(id: "voice", title: "语音输入", count: sources["voice"] ?? 0, color: .indigo),
      StatisticsSlice(id: "unknown", title: "历史未分类", count: sources["unknown"] ?? 0, color: .gray),
    ]
  }

  var body: some View {
    Form {
      Section {
        Picker("统计范围", selection: $period) {
          Text("7 天").tag(7)
          Text("30 天").tag(30)
          Text("累计").tag(0)
        }.pickerStyle(.segmented).accessibilityIdentifier("statisticsPeriod")
          .onChange(of: period) { _ in selectedDay = nil }
        HStack {
          metric("今日输入", count: statistics.count(on: Date()), identifier: "typingToday")
          Spacer()
          metric(scopeTitle, count: scopeTotal, identifier: "typingTotal")
        }.padding(.vertical, 8)
      }
      Section {
        trendChart
        if selectedDay != nil {
          Button("返回整个时间范围") { selectedDay = nil }
        }
      } header: { Text("每日趋势 · 近 \(period == 0 ? 30 : period) 天") }
        footer: { Text("点按柱形查看当天的分类与占比。") }
      Section {
        distribution(characterSlices)
      } header: { Text("字符类型") }
      Section {
        distribution(languageSlices)
      } header: { Text("语言模式") }
        footer: { Text("按提交时使用的键盘模式统计，不推测文本语言；中文模式下输入的数字仍计入中文模式。AI 润色和语音输入单独按来源统计。") }
      Section {
        distribution(sourceSlices)
      } header: { Text("输入方案") }
        footer: { Text("拼音方案统计其上屏字符数，不计未上屏的拼音按键。旧版本总数保留为历史未分类，新输入开始记录细分。") }
      Section {
        Toggle("记录打字统计", isOn: Binding(get: { statistics.enabled }, set: { enabled in
          update { try store.setEnabled(enabled) }
        })).accessibilityIdentifier("typingStatisticsEnabled")
        Button("刷新统计") { reload() }
        Button("清空统计", role: .destructive) { confirmsReset = true }
          .accessibilityIdentifier("resetTypingStatistics")
      } footer: {
        Text("仅统计水杉键盘提交的字符，含标点及表情，不含空格、换行和未上屏拼音。组合表情计为一个字符，删除文字不扣减。仅在本机保存分类计数，不保存输入内容。每日明细保留最近 366 个有记录的日期，累计分类持续保留。")
      }
      Section("开启统计") {
        Text("请在系统设置 → 通用 → 键盘 → 键盘 → 水杉输入法中开启“允许完全访问”，以便键盘将统计写入本机。未开启时仍可正常打字，但不会记录统计。")
        Button("前往系统设置") {
          guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
          UIApplication.shared.open(url)
        }
      }
      if !errorMessage.isEmpty { Section { Text(errorMessage).foregroundStyle(.secondary) } }
    }
    .navigationTitle("打字统计")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { reload() }
    .onChange(of: scenePhase) { if $0 == .active { reload() } }
    .alert("清空所有打字统计？", isPresented: $confirmsReset) {
      Button("取消", role: .cancel) {}
      Button("清空", role: .destructive) { update { try store.reset() }; selectedDay = nil }
    } message: { Text("累计字数、分类和每日记录将被删除，无法恢复。") }
  }

  private var trendChart: some View {
    let maximum = max(1, dates.map { statistics.count(on: $0) }.max() ?? 1)
    return VStack(alignment: .leading, spacing: 8) {
      Text("最高 \(maximum == 1 && dates.allSatisfy { statistics.count(on: $0) == 0 } ? 0 : maximum) 字符 / 天")
        .font(.caption).foregroundStyle(.secondary)
      HStack(alignment: .bottom, spacing: period == 7 ? 10 : 3) {
        ForEach(dates, id: \.self) { date in
          let count = statistics.count(on: date)
          Button { selectedDay = selectedDay == date ? nil : date } label: {
            VStack(spacing: 4) {
              if period == 7 { Text("\(count)").font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6) }
              RoundedRectangle(cornerRadius: period == 7 ? 5 : 2)
                .fill(selectedDay == date ? Color.orange : MetasequoiaTheme.forest.opacity(selectedDay == nil ? 0.85 : 0.4))
                .frame(height: max(2, 120 * Double(count) / Double(maximum)))
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).contentShape(Rectangle())
          }.buttonStyle(.plain)
            .accessibilityLabel(date.formatted(.dateTime.month().day()))
            .accessibilityValue("\(count) 字符")
            .accessibilityIdentifier("statisticsDay_\(TypingStatistics.dayKey(date))")
        }
      }.frame(height: 145)
      HStack {
        Text(dates.first ?? Date(), format: .dateTime.month().day())
        Spacer()
        Text(dates.last ?? Date(), format: .dateTime.month().day())
      }.font(.caption).foregroundStyle(.secondary)
    }.padding(.vertical, 8).accessibilityElement(children: .contain).accessibilityIdentifier("statisticsTrend")
  }

  private func distribution(_ slices: [StatisticsSlice]) -> some View {
    let total = slices.reduce(0) { $0 + $1.count }
    let visible = slices.filter { $0.count > 0 || $0.id != "unknown" }
    return VStack(spacing: 14) {
      GeometryReader { geometry in
        HStack(spacing: 0) {
          ForEach(slices.filter { $0.count > 0 }) { slice in
            slice.color.frame(width: geometry.size.width * Double(slice.count) / Double(max(1, total)))
          }
        }.frame(maxWidth: .infinity, alignment: .leading)
          .background(Color.secondary.opacity(0.12)).clipShape(Capsule())
      }.frame(height: 18).accessibilityHidden(true)
      if total == 0 { Text("暂无输入记录").font(.subheadline).foregroundStyle(.secondary) }
      ForEach(visible) { slice in
        HStack(spacing: 8) {
          Circle().fill(slice.color).frame(width: 8, height: 8)
          Text(slice.title).font(.subheadline)
          Spacer()
          Text("\(slice.count)").monospacedDigit()
          Text(total == 0 ? "—" : "\(Double(slice.count) / Double(total) * 100, specifier: "%.1f")%")
            .font(.caption).foregroundStyle(.secondary).monospacedDigit().frame(width: 54, alignment: .trailing)
        }.accessibilityElement(children: .combine)
      }
    }.padding(.vertical, 8)
  }

  private func metric(_ title: String, count: Int, identifier: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.subheadline).foregroundStyle(.secondary)
      Text("\(count)").font(.system(size: 30, weight: .semibold, design: .rounded))
        .foregroundStyle(MetasequoiaTheme.forest).accessibilityIdentifier(identifier)
      Text("字符").font(.caption).foregroundStyle(.secondary)
    }
  }
  private func reload() { update {} }
  private func update(_ operation: () throws -> Void) {
    do {
      try operation()
      statistics = try store.load()
      errorMessage = ""
    } catch { errorMessage = "暂时无法读取或保存统计，请解锁设备后重试。" }
  }
}
