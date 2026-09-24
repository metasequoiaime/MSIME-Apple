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
          // 选中标记要和折线分得开,而折线是强调色,所以这里用主题里那支暖色,不是系统橙。
          .foregroundStyle(MetasequoiaTheme.cone)
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
/// 列数按可用宽度铺满,不按「有多少天记录」算 —— 只用了一周的人,按记录算就只有一两列,右边整片空着。没有记录的日子画成最浅的一档,和 GitHub 上没提交的日子一样,那是信息不是空白。
struct StatisticsHeatmap: View {
  /// 某一天多少字。热力图自己决定画哪些天,所以要的是一个能按日期问的闭包,不是排好的数组。
  let count: (Date) -> Int
  let selected: Date?
  let accent: Color
  let onSelect: (Date) -> Void

  private static let cell: CGFloat = 15
  private static let spacing: CGFloat = 3
  private static let labelWidth: CGFloat = 12
  /// 最多画一年；这是图表的宽度上限，不是保留期限。
  private static let maximumWeeks = 53
  private var calendar: Calendar { Calendar.current }

  /// 这一屏放得下几列。放不下的可以左右拖,放得下就铺满。
  private func weekCount(for width: CGFloat) -> Int {
    let usable = width - Self.labelWidth - 6
    let perColumn = Self.cell + Self.spacing
    return max(4, min(Self.maximumWeeks, Int(usable / perColumn)))
  }

  /// 从今天所在的那一周往回数 `weeks` 列,每列七天。今天之后的格子留空。
  private func columns(weeks: Int) -> [[Date?]] {
    let today = calendar.startOfDay(for: Date())
    let weekday = calendar.component(.weekday, from: today) - 1
    guard let thisSunday = calendar.date(byAdding: .day, value: -weekday, to: today),
          let start = calendar.date(byAdding: .day, value: -7 * (weeks - 1), to: thisSunday)
    else { return [] }
    return (0..<weeks).map { column in
      (0..<7).map { row in
        guard let date = calendar.date(byAdding: .day, value: column * 7 + row, to: start) else { return nil }
        return date > today ? nil : date
      }
    }
  }

  private func peak(_ grid: [[Date?]]) -> Int {
    max(1, grid.flatMap { $0 }.compactMap { $0 }.map(count).max() ?? 1)
  }

  /// 这一列要不要标月份:出现新的月份就标,和 GitHub 一样。
  private func monthLabel(at index: Int, in grid: [[Date?]]) -> String? {
    guard let current = grid[index].compactMap({ $0 }).first else { return nil }
    let month = calendar.component(.month, from: current)
    guard index > 0, let previous = grid[index - 1].compactMap({ $0 }).first else { return "\(month) 月" }
    return calendar.component(.month, from: previous) == month ? nil : "\(month) 月"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      GeometryReader { geometry in
        let grid = columns(weeks: weekCount(for: geometry.size.width))
        let maximum = peak(grid)
        // 周几那一列钉在滚动区外面 —— 放进去的话,一滚到最近几周它就跟着跑出屏幕。
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
                    ForEach(0..<7, id: \.self) { row in cellView(week[row], maximum: maximum) }
                  }.id(index)
                }
              }
            }
            .disablingScrollEdgeEffects()
            .onAppear { proxy.scrollTo(max(0, grid.count - 1), anchor: .trailing) }
          }
        }
      }.frame(height: 12 + 7 * Self.cell + 6 * Self.spacing)
      legend
    }
    .accessibilityIdentifier("statisticsHeatmap")
  }

  /// 只标一三五 —— 七行都标会把格子挤没,GitHub 也是隔行标。
  private var weekdayLabels: some View {
    VStack(spacing: Self.spacing) {
      ForEach(0..<7, id: \.self) { row in
        Text(["", "一", "", "三", "", "五", ""][row])
          .font(.system(size: 9)).foregroundStyle(.secondary)
          .frame(width: Self.labelWidth, height: Self.cell)
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

  @ViewBuilder private func cellView(_ date: Date?, maximum: Int) -> some View {
    if let date {
      let value = count(date)
      let level = Double(value) / Double(maximum)
      Button { onSelect(date) } label: {
        RoundedRectangle(cornerRadius: 3)
          .fill(value == 0 ? Color.secondary.opacity(0.12) : accent.opacity(0.25 + 0.75 * level))
          .frame(width: Self.cell, height: Self.cell)
          .overlay(RoundedRectangle(cornerRadius: 3)
            .strokeBorder(MetasequoiaTheme.cone, lineWidth: isSelected(date) ? 2 : 0))
      }
      .buttonStyle(.plain)
      .accessibilityLabel(date.formatted(.dateTime.month().day()))
      .accessibilityValue("\(value) 字符")
      .accessibilityIdentifier("statisticsDay_\(TypingStatistics.dayKey(date))")
    } else {
      // 今天之后:留空,那些日子还没发生。
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

/// 今日时段:二十四小时每小时一根柱子。没有输入的小时也占一格 —— 只画有输入的那几个小时,上午和深夜就挤成相邻的两根,看不出一天的节奏。
struct StatisticsHourlyChart: View {
  let hours: [Int]
  let accent: Color
  let progress: Double

  var body: some View {
    Chart(Array(hours.enumerated()), id: \.offset) { hour, count in
      BarMark(x: .value("时", hour), y: .value("字符", Double(count) * progress))
        .cornerRadius(3)
        .foregroundStyle(accent)
    }
    .chartXScale(domain: -0.5...23.5)
    .chartXAxis {
      AxisMarks(values: [0, 6, 12, 18, 23]) { value in
        AxisGridLine()
        AxisValueLabel { if let hour = value.as(Int.self) { Text("\(hour)时") } }
      }
    }
    .chartYAxis { AxisMarks(position: .trailing) }
    .frame(height: 140)
    .accessibilityIdentifier("statisticsHours")
  }
}
