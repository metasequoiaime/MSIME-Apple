import Charts
import SwiftUI

/// 统计页的四张图。
///
/// 四个标签原来画的是同一种东西:一条按比例分段的长条,加一列数字。一屏之内换四次标签、看四次同样的形状,等于没换。每一块现在按它自己的问题选图形 —— 趋势是时间,用折线和日历热力图;类型和模式是「占了多大一块」,用饼图和环形图;方案是「谁多谁少」,用横向排行。
///
/// 图形本身交给 Swift Charts(iOS 16 起),不自己画路径:轴、比例、可访问性它都管了。
enum StatisticsChart {
  /// 一天的输入量。
  struct Day: Identifiable {
    let date: Date
    let count: Int
    var id: Date { date }
  }

  /// 一个分类。
  struct Slice: Identifiable {
    let id: String
    let title: String
    let count: Int
    let color: Color
    let symbol: String
  }
}

/// 每日趋势:折线加渐变面积。
struct StatisticsTrendChart: View {
  let days: [StatisticsChart.Day]
  let selected: Date?
  let accent: Color
  /// 进场时从左往右画出来。
  let progress: Double

  /// 窗口长到几个月时,每天一个点画出来是一片锯齿 —— 看得见每天的起伏,看不出这个月比上个月多。日值退成淡淡的面积,趋势交给七日均线。
  private var isLongRange: Bool { days.count > 120 }
  private var average: [StatisticsChart.Day] {
    days.enumerated().map { index, day in
      let window = days[max(0, index - 6)...index]
      return StatisticsChart.Day(date: day.date, count: window.reduce(0) { $0 + $1.count } / window.count)
    }
  }

  var body: some View {
    Chart {
      ForEach(days) { day in
        AreaMark(x: .value("日期", day.date), y: .value("字符", day.count))
          .interpolationMethod(.catmullRom)
          .foregroundStyle(.linearGradient(
            colors: [accent.opacity(isLongRange ? 0.18 : 0.35), accent.opacity(0.02)],
            startPoint: .top, endPoint: .bottom))
      }
      ForEach(isLongRange ? average : days) { day in
        LineMark(x: .value("日期", day.date), y: .value("字符", day.count))
          .interpolationMethod(.catmullRom)
          .foregroundStyle(accent)
          .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
      }
      if let selected, let day = days.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selected) }) {
        PointMark(x: .value("日期", day.date), y: .value("字符", day.count))
          .foregroundStyle(.orange)
          .symbolSize(90)
      }
    }
    .chartXAxis {
      // 窗口可能是三十天也可能是一年:短的按周标日期,长的按月标月份,否则标签挤成一条黑线。
      if days.count > 120 {
        AxisMarks(values: .stride(by: .month)) { _ in
          AxisGridLine()
          AxisValueLabel(format: .dateTime.month())
        }
      } else {
        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
          AxisGridLine()
          AxisValueLabel(format: .dateTime.month().day())
        }
      }
    }
    .chartYAxis { AxisMarks(position: .trailing) }
    // 折线从左往右画出来:一整条直接出现,看不出它是按时间排的。
    .mask(alignment: .leading) {
      GeometryReader { geometry in
        Rectangle().frame(width: geometry.size.width * progress)
      }
    }
    .frame(height: 170)
    .accessibilityIdentifier("statisticsTrendChart")
  }
}

/// 日历热力图,照 GitHub 的排法:一列是一个自然周,一行是周几,周日在最上,上面标月份、左边标周几。点一格看那一天。
///
/// 先前是「从第一条记录起每七天切一列」:列和星期对不上,头尾都是残的,整块看过去是一片零碎的空白。星期对齐之后每列都是完整的一周,空着的只有窗口开始之前和今天之后那几格。
struct StatisticsHeatmap: View {
  let days: [StatisticsChart.Day]
  let selected: Date?
  let accent: Color
  let onSelect: (Date) -> Void

  private static let cell: CGFloat = 15
  private static let spacing: CGFloat = 3
  private var calendar: Calendar { Calendar.current }
  private var maximum: Int { max(1, days.map(\.count).max() ?? 1) }

  /// 一列一周、每列七格。窗口之外的格子是 nil,留空而不是画成「那天零字」。
  private var columns: [[StatisticsChart.Day?]] {
    guard let first = days.first?.date, let last = days.last?.date else { return [] }
    let firstDay = calendar.startOfDay(for: first)
    let lastDay = calendar.startOfDay(for: last)
    let byDay = Dictionary(days.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { current, _ in current })
    // 退到那一周的周日,列才对得上星期。
    let lead = calendar.component(.weekday, from: firstDay) - 1
    guard var cursor = calendar.date(byAdding: .day, value: -lead, to: firstDay) else { return [] }
    var result: [[StatisticsChart.Day?]] = []
    while cursor <= lastDay {
      var week: [StatisticsChart.Day?] = []
      for offset in 0..<7 {
        guard let date = calendar.date(byAdding: .day, value: offset, to: cursor) else { continue }
        week.append(date < firstDay || date > lastDay ? nil : byDay[date])
      }
      result.append(week)
      guard let next = calendar.date(byAdding: .day, value: 7, to: cursor) else { break }
      cursor = next
    }
    return result
  }

  /// 这一列要不要标月份:出现新的月份就标,和 GitHub 一样。
  private func monthLabel(at index: Int, in columns: [[StatisticsChart.Day?]]) -> String? {
    guard let current = columns[index].compactMap({ $0 }).first?.date else { return nil }
    let month = calendar.component(.month, from: current)
    guard index > 0, let previous = columns[index - 1].compactMap({ $0 }).first?.date else { return "\(month) 月" }
    return calendar.component(.month, from: previous) == month ? nil : "\(month) 月"
  }

  var body: some View {
    let grid = columns
    return VStack(alignment: .leading, spacing: 6) {
      // 周几那一列钉在外面 —— 放进滚动区里,一滚到最近的几周,它就跟着跑出屏幕了。
      HStack(alignment: .top, spacing: 6) {
        weekdayLabels
        ScrollViewReader { proxy in
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Self.spacing) {
              ForEach(Array(grid.enumerated()), id: \.offset) { index, week in
                VStack(alignment: .leading, spacing: Self.spacing) {
                  Text(monthLabel(at: index, in: grid) ?? " ")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(width: Self.cell, height: 12, alignment: .leading)
                  ForEach(0..<7, id: \.self) { row in cellView(week[row]) }
                }.id(index)
              }
            }
          }
          .disablingScrollEdgeEffects()
          .onAppear { proxy.scrollTo(max(0, grid.count - 1), anchor: .trailing) }
        }
      }
      legend
    }
    .accessibilityIdentifier("statisticsHeatmap")
  }

  /// 只标一三五 —— 七行都标就把格子挤没了,GitHub 也是隔行标。
  private var weekdayLabels: some View {
    VStack(spacing: Self.spacing) {
      ForEach(0..<7, id: \.self) { row in
        Text(["", "一", "", "三", "", "五", ""][row])
          .font(.system(size: 9)).foregroundStyle(.secondary)
          .frame(width: 12, height: Self.cell)
      }
    }.padding(.top, 15)
  }

  private var legend: some View {
    HStack(spacing: 5) {
      Text("少").font(.caption2).foregroundStyle(.secondary)
      ForEach([0.0, 0.25, 0.5, 0.75, 1.0], id: \.self) { level in
        RoundedRectangle(cornerRadius: 2)
          .fill(level == 0 ? Color.secondary.opacity(0.12) : accent.opacity(0.25 + 0.75 * level))
          .frame(width: 12, height: 12)
      }
      Text("多").font(.caption2).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private func cellView(_ day: StatisticsChart.Day?) -> some View {
    if let day {
      let level = Double(day.count) / Double(maximum)
      Button { onSelect(day.date) } label: {
        RoundedRectangle(cornerRadius: 3)
          .fill(day.count == 0 ? Color.secondary.opacity(0.12) : accent.opacity(0.25 + 0.75 * level))
          .frame(width: Self.cell, height: Self.cell)
          .overlay(RoundedRectangle(cornerRadius: 3)
            .strokeBorder(Color.orange, lineWidth: isSelected(day.date) ? 2 : 0))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(day.date.formatted(.dateTime.month().day()))
      .accessibilityValue("\(day.count) 字符")
      .accessibilityIdentifier("statisticsDay_\(TypingStatistics.dayKey(day.date))")
    } else {
      Color.clear.frame(width: Self.cell, height: Self.cell)
    }
  }

  private func isSelected(_ date: Date) -> Bool {
    guard let selected else { return false }
    return calendar.isDate(date, inSameDayAs: selected)
  }
}

/// 饼图:看一类占了整块的多少。
struct StatisticsPieChart: View {
  let slices: [StatisticsChart.Slice]
  let progress: Double

  var body: some View {
    Chart(slices.filter { $0.count > 0 }) { slice in
      SectorMark(angle: .value(slice.title, Double(slice.count) * progress), angularInset: 1.5)
        .cornerRadius(3)
        .foregroundStyle(slice.color)
    }
    .frame(height: 190)
    .accessibilityIdentifier("statisticsPie")
  }
}

/// 环形图:中间留出总数,一眼看到「一共多少、谁占大头」。
struct StatisticsDonutChart: View {
  let slices: [StatisticsChart.Slice]
  let total: Int
  let progress: Double

  var body: some View {
    Chart(slices.filter { $0.count > 0 }) { slice in
      SectorMark(angle: .value(slice.title, Double(slice.count) * progress),
                 innerRadius: .ratio(0.62), angularInset: 1.5)
        .cornerRadius(3)
        .foregroundStyle(slice.color)
    }
    .chartBackground { _ in
      VStack(spacing: 2) {
        Text("\(total)").font(.system(size: 26, weight: .semibold, design: .rounded))
        Text("字符").font(.caption2).foregroundStyle(.secondary)
      }
    }
    .frame(height: 190)
    .accessibilityIdentifier("statisticsDonut")
  }
}

/// 横向排行:方案有十几种,平时只有两三种非零。按量排下来比切成十几瓣的饼看得清。
struct StatisticsRankChart: View {
  let slices: [StatisticsChart.Slice]
  let progress: Double

  private var ranked: [StatisticsChart.Slice] {
    slices.filter { $0.count > 0 }.sorted { $0.count > $1.count }
  }

  var body: some View {
    if ranked.isEmpty {
      Text("暂无输入记录").font(.subheadline).foregroundStyle(.secondary)
    } else {
      Chart(ranked) { slice in
        BarMark(x: .value("字符", Double(slice.count) * progress),
                y: .value("方案", slice.title))
          .cornerRadius(5)
          .foregroundStyle(slice.color)
          .annotation(position: .trailing) {
            Text("\(slice.count)").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
          }
      }
      .chartXAxis(.hidden)
      .frame(height: CGFloat(ranked.count) * 30 + 20)
      .accessibilityIdentifier("statisticsRank")
    }
  }
}
